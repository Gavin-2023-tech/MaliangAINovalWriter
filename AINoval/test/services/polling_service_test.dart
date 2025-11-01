import 'package:flutter_test/flutter_test.dart';
import 'package:ainoval/services/polling_service.dart';

void main() {
  group('PollingConfig Tests', () {
    test('fast config should have 1 second interval', () {
      final config = PollingConfig.fast();
      expect(config.intervalMs, 1000);
    });

    test('standard config should have 3 second interval', () {
      final config = PollingConfig.standard();
      expect(config.intervalMs, 3000);
    });

    test('slow config should have 10 second interval', () {
      final config = PollingConfig.slow();
      expect(config.intervalMs, 10000);
    });

    test('smart config should use exponential backoff', () {
      final config = PollingConfig.smart();
      expect(config.useExponentialBackoff, true);
      expect(config.intervalMs, 1000);
    });
  });

  group('PollingResult Tests', () {
    test('should correctly identify completed result', () {
      final result = PollingResult<String>(
        data: 'test',
        isComplete: true,
        attemptNumber: 1,
        timestamp: DateTime.now(),
      );

      expect(result.isComplete, true);
      expect(result.hasData, true);
      expect(result.hasError, false);
    });

    test('should correctly identify error result', () {
      final result = PollingResult<String>(
        error: 'Test error',
        isComplete: true,
        attemptNumber: 1,
        timestamp: DateTime.now(),
      );

      expect(result.hasError, true);
      expect(result.hasData, false);
    });
  });

  group('PollingService Tests', () {
    test('should start and stop successfully', () async {
      final polling = PollingService<int>();
      
      int callCount = 0;
      
      // 启动轮询
      final future = polling.start(
        fetcher: () async {
          callCount++;
          return callCount;
        },
        stopCondition: (result) => (result.data ?? 0) >= 3,
        config: PollingConfig.fast(maxAttempts: 10),
      );

      // 等待完成
      final result = await future;

      expect(result?.data, greaterThanOrEqualTo(3));
      expect(polling.isActive, false);
      expect(callCount, greaterThanOrEqualTo(3));
    });

    test('should stop on error when continueOnError is false', () async {
      final polling = PollingService<String>();
      
      int callCount = 0;
      
      final future = polling.start(
        fetcher: () async {
          callCount++;
          if (callCount >= 2) {
            throw Exception('Test error');
          }
          return 'success';
        },
        stopCondition: (result) => false,
        config: const PollingConfig(
          intervalMs: 100,
          continueOnError: false,
          maxAttempts: 10,
        ),
      );

      final result = await future;

      expect(result?.hasError, true);
      expect(result?.isComplete, true);
      expect(callCount, 2);
    });

    test('should respect max attempts limit', () async {
      final polling = PollingService<int>();
      
      int callCount = 0;
      
      final future = polling.start(
        fetcher: () async {
          callCount++;
          return callCount;
        },
        stopCondition: (result) => false, // 永不停止
        config: PollingConfig.fast(maxAttempts: 5),
      );

      await future;

      expect(callCount, 5);
    });

    test('should handle timeout correctly', () async {
      final polling = PollingService<int>();
      
      final startTime = DateTime.now();
      
      await polling.start(
        fetcher: () async => 1,
        stopCondition: (result) => false,
        config: const PollingConfig(
          intervalMs: 100,
          timeoutMs: 500,
        ),
      );

      final elapsed = DateTime.now().difference(startTime);
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(400));
      expect(elapsed.inMilliseconds, lessThan(1000));
    });

    test('stream mode should emit multiple results', () async {
      final polling = PollingService<int>();
      
      int callCount = 0;
      final results = <int>[];
      
      final stream = polling.startStream(
        fetcher: () async {
          callCount++;
          return callCount;
        },
        stopCondition: (result) => (result.data ?? 0) >= 5,
        config: PollingConfig.fast(maxAttempts: 10),
      );

      await for (final result in stream) {
        if (result.hasData) {
          results.add(result.data!);
        }
        if (result.isComplete) break;
      }

      expect(results.length, greaterThanOrEqualTo(5));
      expect(results.last, greaterThanOrEqualTo(5));
    });
  });

  group('PollingManager Tests', () {
    late PollingManager manager;

    setUp(() {
      manager = PollingManager();
      manager.stopAll(); // 确保清空
    });

    tearDown(() {
      manager.stopAll();
    });

    test('should manage multiple polling tasks', () async {
      int task1Calls = 0;
      int task2Calls = 0;

      // 启动第一个轮询
      final future1 = manager.startPolling<int>(
        id: 'task1',
        fetcher: () async => ++task1Calls,
        stopCondition: (result) => (result.data ?? 0) >= 3,
        config: PollingConfig.fast(),
      );

      // 启动第二个轮询
      final future2 = manager.startPolling<int>(
        id: 'task2',
        fetcher: () async => ++task2Calls,
        stopCondition: (result) => (result.data ?? 0) >= 5,
        config: PollingConfig.fast(),
      );

      await Future.wait([future1, future2]);

      expect(task1Calls, greaterThanOrEqualTo(3));
      expect(task2Calls, greaterThanOrEqualTo(5));
      expect(manager.activeCount, 0);
    });

    test('should stop specific polling', () async {
      var isCompleted = false;

      // 启动轮询（不会自动停止）
      manager.startPolling<int>(
        id: 'task1',
        fetcher: () async => 1,
        stopCondition: (result) => false,
        config: PollingConfig.fast(maxAttempts: 100),
        onComplete: (result) {
          isCompleted = true;
        },
      );

      // 等待一段时间
      await Future.delayed(const Duration(milliseconds: 200));

      // 手动停止
      manager.stopPolling('task1');

      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.activeCount, 0);
      // Note: onComplete may or may not be called depending on timing
    });

    test('should get statistics', () async {
      // 启动一个轮询
      manager.startPollingStream<int>(
        id: 'task1',
        fetcher: () async => 1,
        stopCondition: (result) => (result.attemptNumber) >= 5,
        config: PollingConfig.fast(),
      );

      await Future.delayed(const Duration(milliseconds: 300));

      final stats = manager.getAllStatistics();
      expect(stats, isNotEmpty);
      
      manager.stopAll();
    });

    test('should replace existing polling with same id', () async {
      int firstTaskCalls = 0;
      int secondTaskCalls = 0;

      // 启动第一个轮询
      manager.startPollingStream<int>(
        id: 'task1',
        fetcher: () async => ++firstTaskCalls,
        stopCondition: (result) => false,
        config: PollingConfig.fast(maxAttempts: 100),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // 启动同ID的第二个轮询（应该替换第一个）
      manager.startPollingStream<int>(
        id: 'task1',
        fetcher: () async => ++secondTaskCalls,
        stopCondition: (result) => (result.data ?? 0) >= 3,
        config: PollingConfig.fast(),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // 第二个任务应该有调用，第一个可能已停止
      expect(secondTaskCalls, greaterThan(0));
      
      manager.stopAll();
    });
  });

  group('Stop Condition Tests', () {
    test('complex stop condition should work correctly', () {
      final polling = PollingService<Map<String, dynamic>>();

      bool stopCondition(PollingResult<Map<String, dynamic>> result) {
        if (result.hasError) return true;
        
        final data = result.data;
        if (data == null) return false;

        // 检查多个条件
        final status = data['status'] as String?;
        final progress = data['progress'] as int?;

        if (status == 'completed' || status == 'failed') return true;
        if (progress != null && progress >= 100) return true;
        if (result.attemptNumber > 50) return true;

        return false;
      }

      // 测试不同场景
      expect(
        stopCondition(PollingResult<Map<String, dynamic>>(
          error: 'error',
          isComplete: false,
          attemptNumber: 1,
          timestamp: DateTime.now(),
        )),
        true,
      );

      expect(
        stopCondition(PollingResult<Map<String, dynamic>>(
          data: {'status': 'completed'},
          isComplete: false,
          attemptNumber: 1,
          timestamp: DateTime.now(),
        )),
        true,
      );

      expect(
        stopCondition(PollingResult<Map<String, dynamic>>(
          data: {'progress': 100},
          isComplete: false,
          attemptNumber: 1,
          timestamp: DateTime.now(),
        )),
        true,
      );

      expect(
        stopCondition(PollingResult<Map<String, dynamic>>(
          data: {'status': 'running', 'progress': 50},
          isComplete: false,
          attemptNumber: 51,
          timestamp: DateTime.now(),
        )),
        true,
      );

      expect(
        stopCondition(PollingResult<Map<String, dynamic>>(
          data: {'status': 'running', 'progress': 50},
          isComplete: false,
          attemptNumber: 10,
          timestamp: DateTime.now(),
        )),
        false,
      );
    });
  });
}
