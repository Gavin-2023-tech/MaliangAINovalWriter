import 'dart:async';
import 'package:ainoval/utils/logger.dart';

/// 轮询配置类
class PollingConfig {
  /// 轮询间隔（毫秒）
  final int intervalMs;
  
  /// 最大轮询次数，null表示无限制
  final int? maxAttempts;
  
  /// 超时时间（毫秒），null表示不超时
  final int? timeoutMs;
  
  /// 是否使用指数退避策略
  final bool useExponentialBackoff;
  
  /// 指数退避的最大间隔（毫秒）
  final int maxBackoffIntervalMs;
  
  /// 指数退避的倍数
  final double backoffMultiplier;
  
  /// 错误时是否继续轮询
  final bool continueOnError;
  
  /// 最大连续错误次数，超过后停止轮询
  final int maxConsecutiveErrors;

  const PollingConfig({
    this.intervalMs = 3000,
    this.maxAttempts,
    this.timeoutMs,
    this.useExponentialBackoff = false,
    this.maxBackoffIntervalMs = 30000,
    this.backoffMultiplier = 1.5,
    this.continueOnError = true,
    this.maxConsecutiveErrors = 5,
  });

  /// 创建一个快速轮询配置（每秒）
  factory PollingConfig.fast({
    int? maxAttempts,
    int? timeoutMs,
  }) {
    return PollingConfig(
      intervalMs: 1000,
      maxAttempts: maxAttempts,
      timeoutMs: timeoutMs,
    );
  }

  /// 创建一个标准轮询配置（3秒）
  factory PollingConfig.standard({
    int? maxAttempts,
    int? timeoutMs,
  }) {
    return PollingConfig(
      intervalMs: 3000,
      maxAttempts: maxAttempts,
      timeoutMs: timeoutMs,
    );
  }

  /// 创建一个慢速轮询配置（10秒）
  factory PollingConfig.slow({
    int? maxAttempts,
    int? timeoutMs,
  }) {
    return PollingConfig(
      intervalMs: 10000,
      maxAttempts: maxAttempts,
      timeoutMs: timeoutMs,
    );
  }

  /// 创建一个智能轮询配置（使用指数退避）
  factory PollingConfig.smart({
    int initialIntervalMs = 1000,
    int? maxAttempts,
    int? timeoutMs,
  }) {
    return PollingConfig(
      intervalMs: initialIntervalMs,
      maxAttempts: maxAttempts,
      timeoutMs: timeoutMs,
      useExponentialBackoff: true,
      maxBackoffIntervalMs: 30000,
      backoffMultiplier: 1.5,
    );
  }
}

/// 轮询结果
class PollingResult<T> {
  final T? data;
  final bool isComplete;
  final String? error;
  final int attemptNumber;
  final DateTime timestamp;

  const PollingResult({
    this.data,
    required this.isComplete,
    this.error,
    required this.attemptNumber,
    required this.timestamp,
  });

  bool get hasError => error != null;
  bool get hasData => data != null;
}

/// 轮询停止条件函数类型
/// 返回 true 表示应该停止轮询
typedef PollingStopCondition<T> = bool Function(PollingResult<T> result);

/// 通用轮询服务
/// 
/// 使用示例：
/// ```dart
/// final polling = PollingService<ImportStatus>();
/// 
/// await polling.start(
///   fetcher: () => apiClient.get('/import/$jobId/status'),
///   parser: (data) => ImportStatus.fromJson(data),
///   stopCondition: (result) {
///     if (result.hasError) return true;
///     if (result.data?.status == 'completed') return true;
///     return false;
///   },
///   config: PollingConfig.smart(maxAttempts: 100),
///   onUpdate: (result) {
///     print('Progress: ${result.data?.progress}%');
///   },
/// );
/// ```
class PollingService<T> {
  final String tag;
  Timer? _timer;
  StreamController<PollingResult<T>>? _controller;
  int _attemptCount = 0;
  int _consecutiveErrors = 0;
  DateTime? _startTime;
  bool _isActive = false;
  int _currentIntervalMs = 0;

  PollingService({this.tag = 'PollingService'});

  /// 是否正在轮询
  bool get isActive => _isActive;

  /// 当前尝试次数
  int get attemptCount => _attemptCount;

  /// 开始轮询
  /// 
  /// [fetcher] 获取数据的函数
  /// [parser] 解析响应数据的函数，可选
  /// [stopCondition] 停止条件，返回true时停止轮询
  /// [config] 轮询配置
  /// [onUpdate] 每次轮询结果回调
  /// [onComplete] 轮询完成回调
  /// [onError] 错误回调
  Future<PollingResult<T>?> start({
    required Future<dynamic> Function() fetcher,
    T Function(dynamic data)? parser,
    required PollingStopCondition<T> stopCondition,
    PollingConfig config = const PollingConfig(),
    void Function(PollingResult<T> result)? onUpdate,
    void Function(PollingResult<T> result)? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_isActive) {
      AppLogger.w(tag, '轮询已在运行中，请先停止');
      return null;
    }

    _isActive = true;
    _attemptCount = 0;
    _consecutiveErrors = 0;
    _startTime = DateTime.now();
    _currentIntervalMs = config.intervalMs;
    _controller = StreamController<PollingResult<T>>.broadcast();

    AppLogger.i(tag, '开始轮询: interval=${config.intervalMs}ms, maxAttempts=${config.maxAttempts}, timeout=${config.timeoutMs}ms');

    PollingResult<T>? lastResult;

    try {
      // 监听流
      final streamSubscription = _controller!.stream.listen(
        (result) {
          lastResult = result;
          onUpdate?.call(result);
          
          if (result.isComplete) {
            onComplete?.call(result);
            stop();
          }
        },
        onError: (error) {
          AppLogger.e(tag, '轮询流错误', error);
          onError?.call(error.toString());
        },
      );

      // 立即执行第一次轮询
      await _poll(fetcher, parser, stopCondition, config);

      // 设置定时器
      _timer = Timer.periodic(Duration(milliseconds: _currentIntervalMs), (_) async {
        await _poll(fetcher, parser, stopCondition, config);
      });

      // 等待完成或超时
      if (config.timeoutMs != null) {
        await Future.delayed(Duration(milliseconds: config.timeoutMs!));
        if (_isActive) {
          AppLogger.w(tag, '轮询超时');
          _addResult(PollingResult<T>(
            isComplete: true,
            error: '轮询超时',
            attemptNumber: _attemptCount,
            timestamp: DateTime.now(),
          ));
          stop();
        }
      } else {
        // 如果没有超时设置，等待停止信号
        await _controller!.stream.firstWhere((result) => result.isComplete);
      }

      await streamSubscription.cancel();
    } catch (e) {
      AppLogger.e(tag, '轮询异常', e);
      onError?.call(e.toString());
    } finally {
      stop();
    }

    return lastResult;
  }

  /// 开始轮询并返回Stream
  Stream<PollingResult<T>> startStream({
    required Future<dynamic> Function() fetcher,
    T Function(dynamic data)? parser,
    required PollingStopCondition<T> stopCondition,
    PollingConfig config = const PollingConfig(),
  }) {
    if (_isActive) {
      throw StateError('轮询已在运行中');
    }

    _isActive = true;
    _attemptCount = 0;
    _consecutiveErrors = 0;
    _startTime = DateTime.now();
    _currentIntervalMs = config.intervalMs;
    _controller = StreamController<PollingResult<T>>.broadcast();

    AppLogger.i(tag, '开始轮询流: interval=${config.intervalMs}ms');

    // 立即执行第一次轮询
    _poll(fetcher, parser, stopCondition, config);

    // 设置定时器
    _timer = Timer.periodic(Duration(milliseconds: _currentIntervalMs), (_) {
      _poll(fetcher, parser, stopCondition, config);
    });

    // 超时控制
    if (config.timeoutMs != null) {
      Future.delayed(Duration(milliseconds: config.timeoutMs!)).then((_) {
        if (_isActive) {
          AppLogger.w(tag, '轮询超时');
          _addResult(PollingResult<T>(
            isComplete: true,
            error: '轮询超时',
            attemptNumber: _attemptCount,
            timestamp: DateTime.now(),
          ));
          stop();
        }
      });
    }

    return _controller!.stream;
  }

  /// 执行一次轮询
  Future<void> _poll(
    Future<dynamic> Function() fetcher,
    T Function(dynamic data)? parser,
    PollingStopCondition<T> stopCondition,
    PollingConfig config,
  ) async {
    if (!_isActive) return;

    _attemptCount++;

    // 检查最大尝试次数
    if (config.maxAttempts != null && _attemptCount > config.maxAttempts!) {
      AppLogger.i(tag, '达到最大轮询次数: ${config.maxAttempts}');
      _addResult(PollingResult<T>(
        isComplete: true,
        error: '达到最大轮询次数',
        attemptNumber: _attemptCount,
        timestamp: DateTime.now(),
      ));
      return;
    }

    try {
      final response = await fetcher();
      final data = parser != null ? parser(response) : response as T;

      _consecutiveErrors = 0; // 重置错误计数

      final result = PollingResult<T>(
        data: data,
        isComplete: stopCondition(PollingResult<T>(
          data: data,
          isComplete: false,
          attemptNumber: _attemptCount,
          timestamp: DateTime.now(),
        )),
        attemptNumber: _attemptCount,
        timestamp: DateTime.now(),
      );

      AppLogger.d(tag, '轮询结果 #$_attemptCount: isComplete=${result.isComplete}, hasData=${result.hasData}');
      _addResult(result);

      // 如果使用指数退避，调整间隔
      if (config.useExponentialBackoff && !result.isComplete) {
        _updateInterval(config);
      }
    } catch (e) {
      _consecutiveErrors++;
      AppLogger.e(tag, '轮询错误 #$_attemptCount (连续错误: $_consecutiveErrors)', e);

      final result = PollingResult<T>(
        isComplete: !config.continueOnError || _consecutiveErrors >= config.maxConsecutiveErrors,
        error: e.toString(),
        attemptNumber: _attemptCount,
        timestamp: DateTime.now(),
      );

      _addResult(result);

      if (_consecutiveErrors >= config.maxConsecutiveErrors) {
        AppLogger.e(tag, '达到最大连续错误次数: ${config.maxConsecutiveErrors}');
      }
    }
  }

  /// 更新轮询间隔（指数退避）
  void _updateInterval(PollingConfig config) {
    final newInterval = (_currentIntervalMs * config.backoffMultiplier).toInt();
    _currentIntervalMs = newInterval > config.maxBackoffIntervalMs 
        ? config.maxBackoffIntervalMs 
        : newInterval;

    // 重新设置定时器
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _currentIntervalMs), (_) async {
      await _poll(
        () => Future.error('Timer callback requires original fetcher'),
        null,
        (_) => false,
        config,
      );
    });

    AppLogger.d(tag, '调整轮询间隔: $_currentIntervalMs ms');
  }

  /// 添加结果到流
  void _addResult(PollingResult<T> result) {
    if (_controller?.isClosed == false) {
      _controller!.add(result);
    }
  }

  /// 停止轮询
  void stop() {
    if (!_isActive) return;

    AppLogger.i(tag, '停止轮询: 共执行 $_attemptCount 次, 耗时 ${DateTime.now().difference(_startTime!).inSeconds}秒');
    
    _isActive = false;
    _timer?.cancel();
    _timer = null;
    
    if (_controller?.isClosed == false) {
      _controller?.close();
    }
    _controller = null;
  }

  /// 获取轮询统计信息
  Map<String, dynamic> getStatistics() {
    return {
      'isActive': _isActive,
      'attemptCount': _attemptCount,
      'consecutiveErrors': _consecutiveErrors,
      'currentIntervalMs': _currentIntervalMs,
      'elapsedSeconds': _startTime != null 
          ? DateTime.now().difference(_startTime!).inSeconds 
          : 0,
    };
  }
}

/// 轮询管理器 - 管理多个轮询任务
class PollingManager {
  static final PollingManager _instance = PollingManager._internal();
  factory PollingManager() => _instance;
  PollingManager._internal();

  final Map<String, PollingService> _pollings = {};

  /// 创建并启动一个新的轮询任务
  Future<PollingResult<T>?> startPolling<T>({
    required String id,
    required Future<dynamic> Function() fetcher,
    T Function(dynamic data)? parser,
    required PollingStopCondition<T> stopCondition,
    PollingConfig config = const PollingConfig(),
    void Function(PollingResult<T> result)? onUpdate,
    void Function(PollingResult<T> result)? onComplete,
    void Function(String error)? onError,
  }) async {
    // 如果已存在同ID的轮询，先停止
    if (_pollings.containsKey(id)) {
      AppLogger.w('PollingManager', '停止已存在的轮询: $id');
      _pollings[id]?.stop();
    }

    final polling = PollingService<T>(tag: 'Polling[$id]');
    _pollings[id] = polling;

    try {
      return await polling.start(
        fetcher: fetcher,
        parser: parser,
        stopCondition: stopCondition,
        config: config,
        onUpdate: onUpdate,
        onComplete: (result) {
          onComplete?.call(result);
          _pollings.remove(id);
        },
        onError: (error) {
          onError?.call(error);
          _pollings.remove(id);
        },
      );
    } catch (e) {
      _pollings.remove(id);
      rethrow;
    }
  }

  /// 开始轮询并返回Stream
  Stream<PollingResult<T>> startPollingStream<T>({
    required String id,
    required Future<dynamic> Function() fetcher,
    T Function(dynamic data)? parser,
    required PollingStopCondition<T> stopCondition,
    PollingConfig config = const PollingConfig(),
  }) {
    // 如果已存在同ID的轮询，先停止
    if (_pollings.containsKey(id)) {
      AppLogger.w('PollingManager', '停止已存在的轮询: $id');
      _pollings[id]?.stop();
    }

    final polling = PollingService<T>(tag: 'Polling[$id]');
    _pollings[id] = polling;

    return polling.startStream(
      fetcher: fetcher,
      parser: parser,
      stopCondition: stopCondition,
      config: config,
    );
  }

  /// 停止指定的轮询
  void stopPolling(String id) {
    if (_pollings.containsKey(id)) {
      AppLogger.i('PollingManager', '停止轮询: $id');
      _pollings[id]?.stop();
      _pollings.remove(id);
    }
  }

  /// 停止所有轮询
  void stopAll() {
    AppLogger.i('PollingManager', '停止所有轮询: ${_pollings.length}个');
    for (var polling in _pollings.values) {
      polling.stop();
    }
    _pollings.clear();
  }

  /// 获取所有轮询的统计信息
  Map<String, dynamic> getAllStatistics() {
    return _pollings.map((id, polling) => 
      MapEntry(id, polling.getStatistics())
    );
  }

  /// 获取活跃轮询数量
  int get activeCount => _pollings.values.where((p) => p.isActive).length;
}
