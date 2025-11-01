import 'dart:async';
import 'package:ainoval/models/import_status.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';
import 'package:ainoval/services/polling_service.dart';

/// API轮询服务使用示例
/// 
/// 本文件展示了如何在不同场景下使用PollingService和PollingManager

// ============================================================================
// 示例1: 基础用法 - 监控小说导入进度
// ============================================================================

Future<void> example1_basicUsage() async {
  final apiClient = ApiClient();
  final jobId = 'import_job_123';

  // 创建轮询服务实例
  final polling = PollingService<ImportStatus>(tag: 'ImportPolling');

  try {
    final result = await polling.start(
      // 数据获取函数
      fetcher: () async {
        final response = await apiClient.get('/novels/import/$jobId/status');
        return response;
      },

      // 响应解析函数
      parser: (data) {
        if (data is Map<String, dynamic>) {
          return ImportStatus.fromJson(data);
        }
        throw Exception('无效的响应格式');
      },

      // 停止条件
      stopCondition: (result) {
        if (result.hasError) return true;
        
        final status = result.data?.status;
        return status == 'completed' || status == 'failed';
      },

      // 轮询配置
      config: PollingConfig.smart(
        initialIntervalMs: 1000,
        maxAttempts: 100,
      ),

      // 进度回调
      onUpdate: (result) {
        if (result.hasData) {
          print('导入进度: ${result.data!.progress}%');
          print('状态消息: ${result.data!.message}');
        }
      },

      // 完成回调
      onComplete: (result) {
        if (result.data?.status == 'completed') {
          print('导入成功！');
        } else {
          print('导入失败: ${result.data?.error}');
        }
      },

      // 错误回调
      onError: (error) {
        print('轮询错误: $error');
      },
    );

    print('最终结果: ${result?.data?.status}');
  } finally {
    polling.stop();
  }
}

// ============================================================================
// 示例2: Stream模式 - 实时监听任务状态
// ============================================================================

class TaskStatus {
  final String taskId;
  final String status;
  final int progress;
  final String? message;
  final dynamic result;

  TaskStatus({
    required this.taskId,
    required this.status,
    required this.progress,
    this.message,
    this.result,
  });

  factory TaskStatus.fromJson(Map<String, dynamic> json) {
    return TaskStatus(
      taskId: json['taskId'] ?? '',
      status: json['status'] ?? '',
      progress: json['progress'] ?? 0,
      message: json['message'],
      result: json['result'],
    );
  }

  bool get isFinished => 
      status == 'COMPLETED' || status == 'FAILED' || status == 'CANCELLED';
}

StreamSubscription? example2_streamMode(String taskId, ApiClient apiClient) {
  final polling = PollingService<TaskStatus>(tag: 'TaskPolling');

  final stream = polling.startStream(
    fetcher: () => apiClient.post('/polling/tasks/$taskId/status'),
    
    parser: (data) => TaskStatus.fromJson(data as Map<String, dynamic>),
    
    stopCondition: (result) => result.data?.isFinished ?? false,
    
    config: PollingConfig(
      intervalMs: 3000,
      timeoutMs: 300000, // 5分钟超时
      useExponentialBackoff: true,
    ),
  );

  return stream.listen(
    (result) {
      if (result.hasData) {
        final task = result.data!;
        print('[$taskId] ${task.status} - ${task.progress}%');
        print('消息: ${task.message}');

        if (task.isFinished) {
          if (task.status == 'COMPLETED') {
            print('任务完成! 结果: ${task.result}');
          } else {
            print('任务失败或被取消');
          }
        }
      } else if (result.hasError) {
        print('错误: ${result.error}');
      }
    },
    onError: (error) {
      print('流错误: $error');
    },
    onDone: () {
      print('轮询完成');
      polling.stop();
    },
  );
}

// ============================================================================
// 示例3: 使用PollingManager管理多个轮询任务
// ============================================================================

class MultiTaskPollingExample {
  final PollingManager _manager = PollingManager();
  final ApiClient _apiClient = ApiClient();

  // 启动多个导入任务的轮询
  Future<void> startImportPolling(List<String> jobIds) async {
    for (final jobId in jobIds) {
      await _manager.startPolling<ImportStatus>(
        id: 'import_$jobId',
        
        fetcher: () => _apiClient.get('/novels/import/$jobId/status'),
        
        parser: (data) => ImportStatus.fromJson(data as Map<String, dynamic>),
        
        stopCondition: (result) {
          final status = result.data?.status;
          return status == 'completed' || status == 'failed';
        },
        
        config: PollingConfig.smart(),
        
        onUpdate: (result) {
          print('[$jobId] ${result.data?.progress}%');
        },
        
        onComplete: (result) {
          print('[$jobId] 完成');
          _manager.stopPolling('import_$jobId');
        },
      );
    }
  }

  // 获取所有轮询的统计信息
  void printStatistics() {
    final stats = _manager.getAllStatistics();
    print('活跃轮询数: ${_manager.activeCount}');
    print('详细统计: $stats');
  }

  // 停止所有轮询
  void stopAll() {
    _manager.stopAll();
  }
}

// ============================================================================
// 示例4: 不同的轮询配置策略
// ============================================================================

class PollingConfigExamples {
  // 快速轮询 - 适用于短时任务
  PollingConfig fastConfig() {
    return PollingConfig.fast(
      maxAttempts: 60,  // 最多1分钟
      timeoutMs: 60000,
    );
  }

  // 标准轮询 - 适用于中等时长任务
  PollingConfig standardConfig() {
    return PollingConfig.standard(
      maxAttempts: 100,  // 最多5分钟
      timeoutMs: 300000,
    );
  }

  // 慢速轮询 - 适用于长时任务
  PollingConfig slowConfig() {
    return PollingConfig.slow(
      maxAttempts: 360,   // 最多1小时
      timeoutMs: 3600000,
    );
  }

  // 智能轮询 - 使用指数退避
  PollingConfig smartConfig() {
    return PollingConfig.smart(
      initialIntervalMs: 1000,     // 从1秒开始
      maxAttempts: 200,
    );
  }

  // 自定义配置
  PollingConfig customConfig() {
    return PollingConfig(
      intervalMs: 5000,              // 5秒间隔
      maxAttempts: 50,               // 最多50次
      timeoutMs: 600000,             // 10分钟超时
      useExponentialBackoff: true,   // 使用指数退避
      maxBackoffIntervalMs: 60000,   // 最大间隔1分钟
      backoffMultiplier: 2.0,        // 每次翻倍
      continueOnError: true,         // 出错继续
      maxConsecutiveErrors: 3,       // 最多连续3次错误
    );
  }
}

// ============================================================================
// 示例5: 复杂的停止条件
// ============================================================================

PollingStopCondition<ImportStatus> createComplexStopCondition() {
  int unchangedCount = 0;
  int? lastProgress;

  return (result) {
    // 1. 有错误就停止
    if (result.hasError) {
      print('检测到错误，停止轮询');
      return true;
    }

    final data = result.data;
    if (data == null) return false;

    // 2. 任务完成状态
    if (data.status == 'completed' || data.status == 'failed') {
      print('任务已完成，停止轮询');
      return true;
    }

    // 3. 进度达到100%
    if (data.progress >= 100) {
      print('进度100%，停止轮询');
      return true;
    }

    // 4. 进度长时间不变（可能卡住了）
    if (lastProgress != null && lastProgress == data.progress) {
      unchangedCount++;
      if (unchangedCount >= 10) {
        print('进度10次未变化，可能卡住，停止轮询');
        return true;
      }
    } else {
      unchangedCount = 0;
    }
    lastProgress = data.progress;

    // 5. 尝试次数过多
    if (result.attemptNumber > 100) {
      print('尝试次数过多，停止轮询');
      return true;
    }

    return false;
  };
}

// ============================================================================
// 示例6: 与UI集成的完整示例
// ============================================================================

class ImportProgressWidget {
  final ApiClient _apiClient = ApiClient();
  PollingService<ImportStatus>? _polling;
  
  // 状态变量
  String? jobId;
  int progress = 0;
  String message = '';
  String status = 'idle';

  // 开始导入并监控
  Future<void> startImportWithPolling(String fileName, List<int> fileBytes) async {
    try {
      // 1. 开始导入任务
      jobId = await _apiClient.importNovel(fileBytes, fileName);
      
      // 2. 开始轮询监控
      _polling = PollingService<ImportStatus>(tag: 'ImportProgress');
      
      await _polling!.start(
        fetcher: () => _apiClient.get('/novels/import/$jobId/status'),
        
        parser: (data) => ImportStatus.fromJson(data as Map<String, dynamic>),
        
        stopCondition: (result) {
          final st = result.data?.status;
          return st == 'completed' || st == 'failed';
        },
        
        config: PollingConfig.smart(
          initialIntervalMs: 1000,
          maxAttempts: 300,
          timeoutMs: 600000,  // 10分钟
        ),
        
        onUpdate: (result) {
          if (result.hasData) {
            // 更新UI状态
            _updateUI(
              progress: result.data!.progress,
              message: result.data!.message,
              status: result.data!.status,
            );
          }
        },
        
        onComplete: (result) {
          if (result.data?.status == 'completed') {
            _onImportSuccess(result.data!);
          } else {
            _onImportFailed(result.data?.error ?? '未知错误');
          }
        },
        
        onError: (error) {
          _onImportFailed(error);
        },
      );
    } catch (e) {
      _onImportFailed(e.toString());
    }
  }

  // 取消导入
  Future<void> cancelImport() async {
    if (jobId != null) {
      try {
        await _apiClient.cancelImport(jobId!);
        _polling?.stop();
        _updateUI(status: 'cancelled', message: '已取消');
      } catch (e) {
        print('取消失败: $e');
      }
    }
  }

  // 更新UI（在实际应用中，这里应该调用setState或BLoC）
  void _updateUI({int? progress, String? message, String? status}) {
    if (progress != null) this.progress = progress;
    if (message != null) this.message = message;
    if (status != null) this.status = status;
    
    print('UI更新: $status - $progress% - $message');
    // 在实际应用中: setState(() { ... });
  }

  void _onImportSuccess(ImportStatus result) {
    print('导入成功！');
    _updateUI(
      progress: 100,
      status: 'completed',
      message: '导入完成',
    );
  }

  void _onImportFailed(String error) {
    print('导入失败: $error');
    _updateUI(
      status: 'failed',
      message: error,
    );
  }

  // 清理资源
  void dispose() {
    _polling?.stop();
  }
}

// ============================================================================
// 示例7: 长轮询优化示例
// ============================================================================

class LongPollingExample {
  final ApiClient _apiClient = ApiClient();
  
  // 使用长轮询减少请求次数
  Future<void> longPollTaskStatus(String taskId) async {
    String? lastVersion;
    
    while (true) {
      try {
        final response = await _apiClient.post('/polling/tasks/long-poll', data: {
          'taskId': taskId,
          'lastVersion': lastVersion,
          'timeoutSeconds': 30,  // 等待最多30秒
          'onlyOnChange': true,
        });

        final status = TaskStatus.fromJson(response as Map<String, dynamic>);
        lastVersion = response['version'] as String?;
        
        print('任务状态: ${status.status} - ${status.progress}%');
        
        if (status.isFinished) {
          print('任务完成');
          break;
        }
      } catch (e) {
        print('长轮询错误: $e');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }
}

// ============================================================================
// 示例8: 降级策略 - SSE失败时使用轮询
// ============================================================================

class FallbackPollingExample {
  final ApiClient _apiClient = ApiClient();
  
  Stream<ImportStatus> monitorImportWithFallback(String jobId) async* {
    try {
      // 优先尝试使用SSE
      await for (final status in _sseStream(jobId)) {
        yield status;
      }
    } catch (e) {
      print('SSE失败，降级到轮询: $e');
      
      // 降级到轮询
      final polling = PollingService<ImportStatus>();
      await for (final result in polling.startStream(
        fetcher: () => _apiClient.get('/novels/import/$jobId/status'),
        parser: (data) => ImportStatus.fromJson(data as Map<String, dynamic>),
        stopCondition: (result) {
          final st = result.data?.status;
          return st == 'completed' || st == 'failed';
        },
        config: PollingConfig.smart(),
      )) {
        if (result.hasData) {
          yield result.data!;
        }
      }
    }
  }

  Stream<ImportStatus> _sseStream(String jobId) async* {
    // SSE实现（示例）
    throw UnimplementedError('SSE实现');
  }
}

// ============================================================================
// 主函数 - 运行示例
// ============================================================================

void main() async {
  print('=== API轮询服务使用示例 ===\n');

  // 运行示例1
  print('示例1: 基础用法');
  try {
    // await example1_basicUsage();
  } catch (e) {
    print('示例1错误: $e');
  }

  print('\n---\n');

  // 获取管理器统计
  final manager = PollingManager();
  print('活跃轮询数: ${manager.activeCount}');
  print('统计信息: ${manager.getAllStatistics()}');
}
