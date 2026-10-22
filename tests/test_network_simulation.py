import unittest
import random
import time
from collections import deque


# ---------------------------------------------------------------------------
# NetworkSimulator
# ---------------------------------------------------------------------------

class NetworkSimulator:
    """Симулятор ненадёжного сетевого канала."""

    def __init__(self, latency_ms=0, jitter_ms=0, packet_loss_pct=0.0,
                 out_of_order_pct=0.0, seed=None):
        self.latency_ms = latency_ms
        self.jitter_ms = jitter_ms
        self.packet_loss_pct = packet_loss_pct
        self.out_of_order_pct = out_of_order_pct

        self._rng = random.Random(seed)

        self._stats = {
            "sent": 0,
            "received": 0,
            "lost": 0,
            "reordered": 0,
        }

        # Очередь отложенных пакетов: [(deliver_at_ms, packet), ...]
        self._pending = []

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def send(self, packet):
        """
        Отправить пакет через симулированный канал.

        Возвращает пакет (возможно с метаданными задержки) или None при потере.
        При out-of-order возвращает другой ранее задержанный пакет вместо текущего.
        """
        self._stats["sent"] += 1

        # Потеря пакета
        if self._rng.random() < self.packet_loss_pct:
            self._stats["lost"] += 1
            return None

        # Вычисляем задержку
        jitter = self._rng.uniform(-self.jitter_ms, self.jitter_ms)
        delay = max(0.0, self.latency_ms + jitter)
        deliver_at = time.monotonic() * 1000 + delay

        # Решаем: перестановка порядка?
        if self._rng.random() < self.out_of_order_pct and self._pending:
            # Кладём текущий пакет в очередь, а возвращаем первый из очереди
            self._pending.append((deliver_at, packet))
            self._stats["reordered"] += 1
            # Берём самый ранний по времени доставки
            self._pending.sort(key=lambda x: x[0])
            _, early_packet = self._pending.pop(0)
            self._stats["received"] += 1
            return {"packet": early_packet, "delay_ms": delay}

        # Обычная доставка
        self._stats["received"] += 1
        return {"packet": packet, "delay_ms": delay}

    def get_stats(self):
        """Возвращает словарь со статистикой sent/received/lost/reordered."""
        return dict(self._stats)

    def reset_stats(self):
        for k in self._stats:
            self._stats[k] = 0
        self._pending.clear()


# ---------------------------------------------------------------------------
# PlayerStateBuffer
# ---------------------------------------------------------------------------

class PlayerStateBuffer:
    """
    Буфер интерполяции позиций игрока.

    Снапшот: {'timestamp': float, 'x': float, 'y': float,
               'vx': float, 'vy': float}
    """

    def __init__(self, max_snapshots=64):
        self.max_snapshots = max_snapshots
        self._snapshots = deque(maxlen=max_snapshots)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def add_snapshot(self, snap):
        """Добавить снапшот. Снапшоты хранятся в порядке возрастания timestamp."""
        self._snapshots.append(snap)
        # Сортируем при добавлении (обычно снапшоты приходят по порядку,
        # но при out-of-order нужна корректность)
        sorted_snaps = sorted(self._snapshots, key=lambda s: s["timestamp"])
        self._snapshots = deque(sorted_snaps, maxlen=self.max_snapshots)

    def interpolate(self, render_time):
        """
        Интерполированная/экстраполированная позиция на момент render_time.

        Возвращает (x, y).
        """
        snaps = list(self._snapshots)

        if not snaps:
            return (0.0, 0.0)

        if len(snaps) == 1:
            # Единственный снапшот — экстраполяция
            s = snaps[0]
            dt = (render_time - s["timestamp"]) / 1000.0  # ms → s
            return (s["x"] + s["vx"] * dt, s["y"] + s["vy"] * dt)

        # Ищем пару снапшотов, между которыми находится render_time
        for i in range(len(snaps) - 1):
            s0 = snaps[i]
            s1 = snaps[i + 1]
            if s0["timestamp"] <= render_time <= s1["timestamp"]:
                span = s1["timestamp"] - s0["timestamp"]
                if span == 0:
                    return (s1["x"], s1["y"])
                t = (render_time - s0["timestamp"]) / span
                x = s0["x"] + (s1["x"] - s0["x"]) * t
                y = s0["y"] + (s1["y"] - s0["y"]) * t
                return (x, y)

        # render_time за пределами имеющихся снапшотов
        if render_time < snaps[0]["timestamp"]:
            # Слишком рано — экстраполируем назад от первого снапшота
            s = snaps[0]
            dt = (render_time - s["timestamp"]) / 1000.0
            return (s["x"] + s["vx"] * dt, s["y"] + s["vy"] * dt)

        # render_time после последнего снапшота — экстраполяция вперёд
        s = snaps[-1]
        dt = (render_time - s["timestamp"]) / 1000.0
        return (s["x"] + s["vx"] * dt, s["y"] + s["vy"] * dt)

    def snapshot_count(self):
        return len(self._snapshots)


# ---------------------------------------------------------------------------
# PredictionReconciler
# ---------------------------------------------------------------------------

class PredictionReconciler:
    """
    Клиентское предсказание + согласование с сервером.

    Хранит очередь неподтверждённых инпутов и умеет откатиться
    к серверному состоянию, переиграв оставшиеся инпуты.
    """

    def __init__(self, start_x=0.0, start_y=0.0):
        self._x = start_x
        self._y = start_y
        # Очередь: [{'id': int, 'dx': float, 'dy': float}, ...]
        self.pending_inputs = deque()
        self._next_id = 1

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def apply_input(self, dx, dy):
        """
        Применить инпут локально и добавить в очередь неподтверждённых.

        Возвращает назначенный input_id.
        """
        input_id = self._next_id
        self._next_id += 1
        self._x += dx
        self._y += dy
        self.pending_inputs.append({"id": input_id, "dx": dx, "dy": dy})
        return input_id

    def reconcile(self, server_state):
        """
        Согласование с серверным состоянием.

        server_state: {'x': float, 'y': float, 'last_processed_input': int}

        Алгоритм:
        1. Откатиться к серверной позиции.
        2. Убрать из очереди все инпуты с id <= last_processed_input.
        3. Переиграть оставшиеся (неподтверждённые) инпуты.
        """
        last_id = server_state.get("last_processed_input", 0)

        # Убираем подтверждённые инпуты
        while self.pending_inputs and self.pending_inputs[0]["id"] <= last_id:
            self.pending_inputs.popleft()

        # Откат к серверной позиции
        self._x = server_state["x"]
        self._y = server_state["y"]

        # Переигрываем оставшиеся инпуты
        for inp in self.pending_inputs:
            self._x += inp["dx"]
            self._y += inp["dy"]

    def get_position(self):
        """Возвращает текущую предсказанную позицию (x, y)."""
        return (self._x, self._y)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestNetworkSimulator(unittest.TestCase):

    def test_no_loss(self):
        sim = NetworkSimulator(latency_ms=50, packet_loss_pct=0.0, seed=42)
        for i in range(100):
            result = sim.send({"seq": i})
            self.assertIsNotNone(result)
        stats = sim.get_stats()
        self.assertEqual(stats["sent"], 100)
        self.assertEqual(stats["lost"], 0)
        self.assertEqual(stats["received"], 100)

    def test_full_loss(self):
        sim = NetworkSimulator(latency_ms=10, packet_loss_pct=1.0, seed=7)
        for i in range(50):
            result = sim.send({"seq": i})
            self.assertIsNone(result)
        stats = sim.get_stats()
        self.assertEqual(stats["lost"], 50)
        self.assertEqual(stats["received"], 0)

    def test_approximate_half_loss(self):
        sim = NetworkSimulator(packet_loss_pct=0.5, seed=0)
        for i in range(1000):
            sim.send({"seq": i})
        stats = sim.get_stats()
        loss_ratio = stats["lost"] / stats["sent"]
        # Допуск ±10% для 1000 пакетов
        self.assertAlmostEqual(loss_ratio, 0.5, delta=0.1)

    def test_latency_in_result(self):
        sim = NetworkSimulator(latency_ms=100, jitter_ms=0, packet_loss_pct=0.0, seed=1)
        result = sim.send({"data": "test"})
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["delay_ms"], 100.0, delta=0.001)

    def test_jitter_applied(self):
        sim = NetworkSimulator(latency_ms=50, jitter_ms=30, packet_loss_pct=0.0, seed=99)
        delays = []
        for i in range(200):
            r = sim.send({"seq": i})
            if r is not None:
                delays.append(r["delay_ms"])
        # При jitter=30 задержки должны варьироваться в диапазоне [20, 80]
        self.assertGreater(max(delays) - min(delays), 1.0)
        self.assertTrue(all(d >= 0 for d in delays))

    def test_get_stats_keys(self):
        sim = NetworkSimulator()
        sim.send({"x": 1})
        stats = sim.get_stats()
        for key in ("sent", "received", "lost", "reordered"):
            self.assertIn(key, stats)


class TestPlayerStateBuffer(unittest.TestCase):

    def _make_snap(self, ts, x, y, vx=0.0, vy=0.0):
        return {"timestamp": ts, "x": x, "y": y, "vx": vx, "vy": vy}

    def test_interpolation_between_two_snapshots(self):
        buf = PlayerStateBuffer()
        buf.add_snapshot(self._make_snap(0, 0.0, 0.0))
        buf.add_snapshot(self._make_snap(100, 10.0, 20.0))
        # На середине интервала должна быть середина пути
        x, y = buf.interpolate(50)
        self.assertAlmostEqual(x, 5.0, places=5)
        self.assertAlmostEqual(y, 10.0, places=5)

    def test_interpolation_at_exact_snapshot(self):
        buf = PlayerStateBuffer()
        buf.add_snapshot(self._make_snap(0, 1.0, 2.0))
        buf.add_snapshot(self._make_snap(200, 3.0, 6.0))
        x, y = buf.interpolate(0)
        self.assertAlmostEqual(x, 1.0)
        self.assertAlmostEqual(y, 2.0)
        x, y = buf.interpolate(200)
        self.assertAlmostEqual(x, 3.0)
        self.assertAlmostEqual(y, 6.0)

    def test_extrapolation_forward(self):
        buf = PlayerStateBuffer()
        # Скорость vx=10 пикс/с, vy=0; timestamp в ms
        buf.add_snapshot(self._make_snap(0, 0.0, 0.0, vx=10.0, vy=5.0))
        # Запрашиваем на 500ms вперёд (0.5s) → x=5, y=2.5
        x, y = buf.interpolate(500)
        self.assertAlmostEqual(x, 5.0, places=5)
        self.assertAlmostEqual(y, 2.5, places=5)

    def test_extrapolation_with_two_snapshots_past_last(self):
        buf = PlayerStateBuffer()
        buf.add_snapshot(self._make_snap(0, 0.0, 0.0, vx=0.0, vy=0.0))
        buf.add_snapshot(self._make_snap(100, 10.0, 0.0, vx=100.0, vy=0.0))
        # Запрос за последним снапшотом — экстраполяция по vx последнего
        x, y = buf.interpolate(200)
        # dt = (200-100)/1000 = 0.1s; x = 10 + 100*0.1 = 20
        self.assertAlmostEqual(x, 20.0, places=5)

    def test_empty_buffer_returns_zero(self):
        buf = PlayerStateBuffer()
        x, y = buf.interpolate(1000)
        self.assertEqual(x, 0.0)
        self.assertEqual(y, 0.0)

    def test_max_snapshots_respected(self):
        buf = PlayerStateBuffer(max_snapshots=5)
        for i in range(10):
            buf.add_snapshot(self._make_snap(i * 100, float(i), 0.0))
        self.assertLessEqual(buf.snapshot_count(), 5)


class TestPredictionReconciler(unittest.TestCase):

    def test_apply_inputs_accumulate(self):
        rec = PredictionReconciler(0.0, 0.0)
        rec.apply_input(1.0, 0.0)
        rec.apply_input(1.0, 0.0)
        rec.apply_input(0.0, 2.0)
        x, y = rec.get_position()
        self.assertAlmostEqual(x, 2.0)
        self.assertAlmostEqual(y, 2.0)

    def test_reconcile_rollback_and_replay(self):
        """
        Применяем 5 инпутов, сервер подтверждает первые 3 с исправленной позицией,
        клиент должен переиграть инпуты 4 и 5.
        """
        rec = PredictionReconciler(0.0, 0.0)
        # Инпуты: каждый сдвигает на (+10, +5)
        for _ in range(5):
            rec.apply_input(10.0, 5.0)
        # Локально: x=50, y=25
        x, y = rec.get_position()
        self.assertAlmostEqual(x, 50.0)
        self.assertAlmostEqual(y, 25.0)

        # Сервер обработал инпуты 1-3, но с исправленной позицией x=28, y=14
        # (допустим, небольшая коррекция из-за коллизии)
        server_state = {"x": 28.0, "y": 14.0, "last_processed_input": 3}
        rec.reconcile(server_state)

        # После reconcile: server(28,14) + replay inp4(+10,+5) + inp5(+10,+5)
        # x = 28+10+10 = 48, y = 14+5+5 = 24
        x, y = rec.get_position()
        self.assertAlmostEqual(x, 48.0)
        self.assertAlmostEqual(y, 24.0)

    def test_reconcile_clears_confirmed_inputs(self):
        rec = PredictionReconciler(0.0, 0.0)
        for _ in range(5):
            rec.apply_input(1.0, 1.0)
        self.assertEqual(len(rec.pending_inputs), 5)

        rec.reconcile({"x": 3.0, "y": 3.0, "last_processed_input": 3})
        # Должны остаться только инпуты 4 и 5
        self.assertEqual(len(rec.pending_inputs), 2)
        self.assertEqual(rec.pending_inputs[0]["id"], 4)
        self.assertEqual(rec.pending_inputs[1]["id"], 5)

    def test_full_reconcile_no_pending(self):
        rec = PredictionReconciler(0.0, 0.0)
        for _ in range(3):
            rec.apply_input(5.0, 0.0)
        rec.reconcile({"x": 15.0, "y": 0.0, "last_processed_input": 3})
        x, y = rec.get_position()
        self.assertAlmostEqual(x, 15.0)
        self.assertAlmostEqual(y, 0.0)
        self.assertEqual(len(rec.pending_inputs), 0)


class TestStressPacketLoss(unittest.TestCase):

    def test_loss_30_percent_1000_packets(self):
        sim = NetworkSimulator(packet_loss_pct=0.3, seed=12345)
        for i in range(1000):
            sim.send({"seq": i, "payload": "x" * 64})
        stats = sim.get_stats()
        self.assertEqual(stats["sent"], 1000)
        loss_ratio = stats["lost"] / stats["sent"]
        # Допуск ±5%: ожидаем 25-35% потерь
        self.assertGreaterEqual(loss_ratio, 0.25,
            msg=f"Loss ratio {loss_ratio:.3f} ниже нижней границы 0.25")
        self.assertLessEqual(loss_ratio, 0.35,
            msg=f"Loss ratio {loss_ratio:.3f} выше верхней границы 0.35")

    def test_stress_no_crash_mixed_conditions(self):
        sim = NetworkSimulator(
            latency_ms=80,
            jitter_ms=40,
            packet_loss_pct=0.15,
            out_of_order_pct=0.1,
            seed=777,
        )
        received = 0
        for i in range(500):
            r = sim.send({"seq": i})
            if r is not None:
                received += 1
        stats = sim.get_stats()
        self.assertEqual(stats["sent"], 500)
        self.assertEqual(stats["received"] + stats["lost"], 500)


class TestHighLatency(unittest.TestCase):
    """Проверка плавности интерполяции при высокой задержке сети (200ms)."""

    def _make_snap(self, ts, x, y, vx=0.0, vy=0.0):
        return {"timestamp": ts, "x": x, "y": y, "vx": vx, "vy": vy}

    def test_smooth_interpolation_200ms_buffer(self):
        """
        Симулируем ситуацию: снапшоты с сервера приходят каждые 50ms,
        клиент рендерит их с задержкой 200ms (render_time = server_time - 200).
        Позиция должна быть монотонно возрастающей.
        """
        buf = PlayerStateBuffer()
        # Игрок движется равномерно: x увеличивается на 10 каждые 50ms
        server_time_start = 1000.0
        for i in range(20):
            ts = server_time_start + i * 50
            buf.add_snapshot(self._make_snap(ts, float(i * 10), 0.0, vx=200.0, vy=0.0))

        # Рендерим с задержкой 200ms (клиент отстаёт от сервера)
        render_delay = 200.0
        positions = []
        for frame in range(30):
            render_t = server_time_start + frame * 33 - render_delay
            x, y = buf.interpolate(render_t)
            positions.append(x)

        # Проверяем монотонность (каждая следующая позиция >= предыдущей)
        for i in range(1, len(positions)):
            self.assertGreaterEqual(
                positions[i], positions[i - 1] - 0.01,
                msg=f"Нарушение монотонности на кадре {i}: "
                    f"{positions[i]:.3f} < {positions[i-1]:.3f}"
            )

    def test_interpolation_stays_bounded(self):
        """
        Экстраполяция не должна давать безумные значения при разумных скоростях.
        """
        buf = PlayerStateBuffer()
        buf.add_snapshot(self._make_snap(0, 0.0, 0.0, vx=50.0, vy=50.0))
        buf.add_snapshot(self._make_snap(100, 5.0, 5.0, vx=50.0, vy=50.0))

        # Запрос на 500ms после последнего снапшота (0.4s экстраполяции)
        x, y = buf.interpolate(500)
        # x = 5 + 50*(0.4) = 25, y аналогично
        self.assertAlmostEqual(x, 25.0, delta=1.0)
        self.assertAlmostEqual(y, 25.0, delta=1.0)

    def test_high_latency_simulator_with_buffer(self):
        """
        Интеграционный тест: пакеты прогоняются через симулятор с 200ms задержкой,
        буфер получает снапшоты и интерполирует корректно.
        """
        sim = NetworkSimulator(latency_ms=200, jitter_ms=20,
                               packet_loss_pct=0.05, seed=42)
        buf = PlayerStateBuffer()

        base_time = 0.0
        received_count = 0
        for i in range(40):
            snap = {
                "timestamp": base_time + i * 50,
                "x": float(i * 5),
                "y": float(i * 2),
                "vx": 100.0,
                "vy": 40.0,
            }
            result = sim.send(snap)
            if result is not None:
                buf.add_snapshot(result["packet"])
                received_count += 1

        self.assertGreater(received_count, 25,
            msg="Слишком много потерь пакетов — буфер пуст")

        # Интерполяция в середине полученного диапазона не должна вернуть (0,0)
        # если снапшоты есть
        snaps = list(buf._snapshots)
        if len(snaps) >= 2:
            mid_ts = (snaps[0]["timestamp"] + snaps[-1]["timestamp"]) / 2
            x, y = buf.interpolate(mid_ts)
            self.assertGreater(x, 0.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
