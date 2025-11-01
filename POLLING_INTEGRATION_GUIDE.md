# API轮询功能集成指南

本文档说明如何在 AINovalWriter 项目中集成和使用API轮询功能。

## 📋 目录

1. [前端集成](#前端集成)
2. [后端集成](#后端集成)
3. [使用示例](#使用示例)
4. [最佳实践](#最佳实践)
5. [故障排查](#故障排查)

## 前端集成

### 1. 文件结构

API轮询功能相关文件：

```
AINoval/lib/
├── services/
│   ├── polling_service.dart              # 核心轮询服务
│   └── polling_service_example.dart      # 使用示例
└── test/
    └── services/
        └── polling_service_test.dart     # 单元测试
```

### 2. 依赖说明

无需额外依赖，使用Dart标准库即可。

### 3. 在现有代码中使用

#### 方式1: 直接使用 PollingService

```dart
import 'package:ainoval/services/polling_service.dart';
import 'package:ainoval/services/api_service/base/api_client.dart';

class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _apiClient = ApiClient();
  PollingService<TaskStatus>? _polling;
  
  Future<void> startTask() async {
    final taskId = await _startAsyncTask();
    
    _polling = PollingService<TaskStatus>();
    await _polling!.start(
      fetcher: () => _apiClient.post('/polling/tasks/$taskId/status'),
      parser: (data) => TaskStatus.fromJson(data),
      stopCondition: (result) => result.data?.isFinished ?? false,
      config: PollingConfig.smart(),
      onUpdate: (result) {
        setState(() {
          // 更新UI
        });
      },
    );
  }
  
  @override
  void dispose() {
    _polling?.stop();
    super.dispose();
  }
}
```

#### 方式2: 使用 PollingManager（推荐）

```dart
import 'package:ainoval/services/polling_service.dart';

class TaskMonitorService {
  final _manager = PollingManager();
  final _apiClient = ApiClient();
  
  Future<void> monitorTask(String taskId) async {
    await _manager.startPolling<TaskStatus>(
      id: 'task_$taskId',
      fetcher: () => _apiClient.post('/polling/tasks/$taskId/status'),
      parser: (data) => TaskStatus.fromJson(data),
      stopCondition: (result) => result.data?.isFinished ?? false,
      config: PollingConfig.smart(),
      onUpdate: (result) {
        // 通知监听者
        _notifyListeners(result);
      },
    );
  }
  
  void stopMonitoring(String taskId) {
    _manager.stopPolling('task_$taskId');
  }
  
  void dispose() {
    _manager.stopAll();
  }
}
```

### 4. 集成到BLoC

```dart
// 在Event中添加
class StartTaskPolling extends EditorEvent {
  final String taskId;
  const StartTaskPolling(this.taskId);
}

class StopTaskPolling extends EditorEvent {
  final String taskId;
  const StopTaskPolling(this.taskId);
}

// 在Bloc中处理
class EditorBloc extends Bloc<EditorEvent, EditorState> {
  final _pollingManager = PollingManager();
  
  EditorBloc() : super(EditorInitial()) {
    on<StartTaskPolling>(_onStartTaskPolling);
    on<StopTaskPolling>(_onStopTaskPolling);
  }
  
  Future<void> _onStartTaskPolling(
    StartTaskPolling event,
    Emitter<EditorState> emit,
  ) async {
    await _pollingManager.startPolling<TaskStatus>(
      id: 'task_${event.taskId}',
      fetcher: () => apiClient.post('/polling/tasks/${event.taskId}/status'),
      parser: (data) => TaskStatus.fromJson(data),
      stopCondition: (result) => result.data?.isFinished ?? false,
      config: PollingConfig.smart(),
      onUpdate: (result) {
        if (result.hasData) {
          add(TaskStatusUpdated(result.data!));
        }
      },
    );
  }
  
  void _onStopTaskPolling(
    StopTaskPolling event,
    Emitter<EditorState> emit,
  ) {
    _pollingManager.stopPolling('task_${event.taskId}');
  }
  
  @override
  Future<void> close() {
    _pollingManager.stopAll();
    return super.close();
  }
}
```

### 5. 替换现有的轮询逻辑

在 `ai_task_center_panel.dart` 中，可以将现有的手动轮询逻辑替换为：

```dart
// 原代码 (简化)
_pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
  // 手动轮询逻辑
});

// 新代码
_pollingManager.startPollingStream<Map<String, dynamic>>(
  id: 'task_fallback',
  fetcher: () => _repo.getTaskStatus(taskId),
  stopCondition: (result) {
    if (result.hasError) return true;
    final status = result.data?['status'];
    return status == 'COMPLETED' || status == 'FAILED';
  },
  config: PollingConfig.smart(
    initialIntervalMs: 30000, // 30秒
  ),
).listen((result) {
  // 处理结果
});
```

## 后端集成

### 1. 文件结构

```
AINovalServer/src/main/java/com/ainovel/server/
├── web/
│   ├── controller/
│   │   └── PollingController.java            # 轮询接口控制器
│   └── dto/
│       ├── PollingTaskStatusDto.java         # 任务状态DTO
│       └── LongPollingRequest.java           # 长轮询请求DTO
├── service/
│   ├── PollingTaskService.java               # 轮询服务接口
│   ├── impl/
│   │   └── PollingTaskServiceImpl.java       # 轮询服务实现
│   └── example/
│       └── PollingServiceUsageExample.java   # 使用示例
```

### 2. SecurityConfig配置

需要在 `SecurityConfig.java` 中添加轮询接口的路径：

```java
@Bean
public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
    return http
        // ... 其他配置
        .pathMatchers("/api/v1/polling/**").authenticated()  // 添加此行
        // ...
        .build();
}
```

### 3. 在现有Service中使用

#### 示例1: 小说导入服务

```java
@Service
@RequiredArgsConstructor
public class NovelImportService {
    
    private final PollingTaskServiceImpl pollingTaskService;
    
    public String startImport(ImportRequest request) {
        // 创建任务
        String taskId = pollingTaskService.createTask(
            "NOVEL_IMPORT",
            Map.of("fileName", request.getFileName())
        );
        
        // 异步执行
        CompletableFuture.runAsync(() -> {
            try {
                pollingTaskService.updateTaskStatus(
                    taskId, "RUNNING", 0, "开始导入..."
                );
                
                // 执行导入逻辑
                for (int i = 0; i < totalChapters; i++) {
                    processChapter(i);
                    
                    int progress = (i + 1) * 100 / totalChapters;
                    pollingTaskService.updateTaskStatus(
                        taskId, "RUNNING", progress, 
                        "正在导入第 " + (i + 1) + " 章"
                    );
                }
                
                // 完成
                pollingTaskService.updateTaskStatus(
                    taskId, "COMPLETED", 100, "导入完成"
                );
                pollingTaskService.updateTaskResult(taskId, result);
                
            } catch (Exception e) {
                pollingTaskService.updateTaskError(
                    taskId, e.getMessage(), getStackTrace(e)
                );
            }
        });
        
        return taskId;
    }
}
```

#### 示例2: AI生成服务

```java
@Service
@RequiredArgsConstructor
public class AIGenerationService {
    
    private final PollingTaskServiceImpl pollingTaskService;
    
    public String startGeneration(GenerationRequest request) {
        String taskId = pollingTaskService.createTask(
            "AI_GENERATION",
            Map.of("sceneId", request.getSceneId())
        );
        
        CompletableFuture.runAsync(() -> {
            try {
                pollingTaskService.updateTaskStatus(
                    taskId, "RUNNING", 0, "调用AI模型..."
                );
                
                // 调用AI
                String result = callAIModel(request);
                
                pollingTaskService.updateTaskStatus(
                    taskId, "COMPLETED", 100, "生成完成"
                );
                pollingTaskService.updateTaskResult(
                    taskId, Map.of("content", result)
                );
                
            } catch (Exception e) {
                pollingTaskService.updateTaskError(
                    taskId, "生成失败", e.getMessage()
                );
            }
        });
        
        return taskId;
    }
}
```

### 4. 添加定时清理任务

在配置类中添加：

```java
@Configuration
@EnableScheduling
public class SchedulingConfig {
    
    @Autowired
    private PollingTaskServiceImpl pollingTaskService;
    
    @Scheduled(fixedRate = 3600000) // 每小时执行一次
    public void cleanupFinishedTasks() {
        int cleaned = pollingTaskService.cleanupFinishedTasks();
        log.info("清理已完成的任务: {} 个", cleaned);
    }
}
```

### 5. 生产环境优化

对于生产环境，建议使用Redis存储任务状态：

```java
@Service
@RequiredArgsConstructor
public class RedisPollingTaskService implements PollingTaskService {
    
    private final ReactiveRedisTemplate<String, PollingTaskStatusDto> redisTemplate;
    
    @Override
    public Mono<PollingTaskStatusDto> getTaskStatus(String taskId) {
        return redisTemplate.opsForValue()
            .get("polling:task:" + taskId);
    }
    
    public void updateTaskStatus(String taskId, String status, 
                                 Integer progress, String message) {
        String key = "polling:task:" + taskId;
        
        redisTemplate.opsForValue()
            .get(key)
            .flatMap(task -> {
                task.setStatus(status);
                task.setProgress(progress);
                task.setMessage(message);
                
                // 设置过期时间
                return redisTemplate.opsForValue()
                    .set(key, task, Duration.ofHours(24));
            })
            .subscribe();
    }
}
```

## 使用示例

### 完整的小说导入监控示例

**前端 (Flutter)**

```dart
class NovelImportDialog extends StatefulWidget {
  final String fileName;
  final List<int> fileBytes;
  
  const NovelImportDialog({
    required this.fileName,
    required this.fileBytes,
  });
  
  @override
  _NovelImportDialogState createState() => _NovelImportDialogState();
}

class _NovelImportDialogState extends State<NovelImportDialog> {
  final _apiClient = ApiClient();
  final _manager = PollingManager();
  
  String? _jobId;
  int _progress = 0;
  String _message = '准备导入...';
  String _status = 'pending';
  
  @override
  void initState() {
    super.initState();
    _startImport();
  }
  
  Future<void> _startImport() async {
    try {
      // 1. 上传文件
      _jobId = await _apiClient.importNovel(
        widget.fileBytes,
        widget.fileName,
      );
      
      // 2. 开始轮询监控
      await _manager.startPolling<ImportStatus>(
        id: 'import_$_jobId',
        fetcher: () => _apiClient.get('/novels/import/$_jobId/status'),
        parser: (data) => ImportStatus.fromJson(data),
        stopCondition: (result) {
          final status = result.data?.status;
          return status == 'completed' || status == 'failed';
        },
        config: PollingConfig.smart(
          initialIntervalMs: 1000,
          maxAttempts: 300,
        ),
        onUpdate: (result) {
          if (result.hasData) {
            setState(() {
              _progress = result.data!.progress;
              _message = result.data!.message;
              _status = result.data!.status;
            });
          }
        },
        onComplete: (result) {
          if (result.data?.status == 'completed') {
            _onSuccess();
          } else {
            _onError(result.data?.error ?? '导入失败');
          }
        },
      );
    } catch (e) {
      _onError(e.toString());
    }
  }
  
  void _onSuccess() {
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导入成功')),
    );
  }
  
  void _onError(String error) {
    setState(() {
      _status = 'failed';
      _message = error;
    });
  }
  
  Future<void> _cancel() async {
    if (_jobId != null) {
      await _apiClient.cancelImport(_jobId!);
      _manager.stopPolling('import_$_jobId');
    }
    Navigator.of(context).pop(false);
  }
  
  @override
  void dispose() {
    _manager.stopAll();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入进度'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress / 100),
          const SizedBox(height: 16),
          Text(_message),
          Text('$_progress%'),
        ],
      ),
      actions: [
        if (_status == 'running')
          TextButton(
            onPressed: _cancel,
            child: const Text('取消'),
          ),
        if (_status == 'failed')
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
      ],
    );
  }
}
```

**后端 (Spring Boot)**

```java
@RestController
@RequestMapping("/api/v1/novels")
@RequiredArgsConstructor
public class NovelController {
    
    private final NovelImportService novelImportService;
    
    @PostMapping("/import")
    public Mono<Map<String, String>> startImport(
        @RequestPart("file") FilePart file,
        @CurrentUser String userId
    ) {
        return novelImportService.startImport(userId, file)
            .map(jobId -> Map.of("jobId", jobId));
    }
}

@Service
@RequiredArgsConstructor
public class NovelImportService {
    
    private final PollingTaskServiceImpl pollingTaskService;
    
    public Mono<String> startImport(String userId, FilePart file) {
        return file.content()
            .reduce(DataBuffer::write)
            .flatMap(dataBuffer -> {
                byte[] bytes = new byte[dataBuffer.readableByteCount()];
                dataBuffer.read(bytes);
                DataBufferUtils.release(dataBuffer);
                
                // 创建任务
                String taskId = pollingTaskService.createTask(
                    "NOVEL_IMPORT",
                    Map.of(
                        "userId", userId,
                        "fileName", file.filename()
                    )
                );
                
                // 异步执行
                executeImportAsync(taskId, bytes);
                
                return Mono.just(taskId);
            });
    }
    
    private void executeImportAsync(String taskId, byte[] fileContent) {
        CompletableFuture.runAsync(() -> {
            try {
                pollingTaskService.updateTaskStatus(
                    taskId, "RUNNING", 0, "开始导入..."
                );
                
                // 解析文件
                List<Chapter> chapters = parseFile(fileContent);
                int total = chapters.size();
                
                // 逐章处理
                for (int i = 0; i < total; i++) {
                    processChapter(chapters.get(i));
                    
                    int progress = (i + 1) * 100 / total;
                    pollingTaskService.updateTaskStatus(
                        taskId,
                        "RUNNING",
                        progress,
                        String.format("正在导入第 %d/%d 章", i + 1, total)
                    );
                }
                
                // 完成
                pollingTaskService.updateTaskStatus(
                    taskId, "COMPLETED", 100, "导入完成"
                );
                
            } catch (Exception e) {
                log.error("导入失败: taskId={}", taskId, e);
                pollingTaskService.updateTaskError(
                    taskId,
                    "导入失败: " + e.getMessage(),
                    getStackTrace(e)
                );
            }
        });
    }
}
```

## 最佳实践

### 1. 选择合适的轮询策略

```dart
// 快速任务（< 10秒）
PollingConfig.fast(maxAttempts: 60)

// 中等任务（10秒 - 5分钟）
PollingConfig.standard(timeoutMs: 300000)

// 长时任务（> 5分钟）
PollingConfig.smart(
  initialIntervalMs: 1000,
  maxAttempts: 300,
)
```

### 2. 合理设置停止条件

```dart
stopCondition: (result) {
  // 1. 检查错误
  if (result.hasError) return true;
  
  // 2. 检查数据
  if (result.data == null) return false;
  
  // 3. 检查业务状态
  final status = result.data!.status;
  return status == 'completed' || status == 'failed';
}
```

### 3. 优先使用SSE，轮询作为降级

```dart
Stream<ImportStatus> monitorImport(String jobId) async* {
  try {
    // 优先使用SSE
    await for (final status in _sseClient.streamEvents(...)) {
      yield status;
    }
  } catch (e) {
    // 降级到轮询
    final polling = PollingService<ImportStatus>();
    await for (final result in polling.startStream(...)) {
      if (result.hasData) yield result.data!;
    }
  }
}
```

### 4. 资源清理

```dart
@override
void dispose() {
  _pollingManager.stopAll();
  super.dispose();
}
```

### 5. 错误处理

```dart
onError: (error) {
  // 记录日志
  AppLogger.e('Polling', '轮询错误', error);
  
  // 通知用户
  showError('任务失败: $error');
  
  // 清理资源
  _pollingManager.stopAll();
}
```

## 故障排查

### 问题1: 轮询不停止

**原因**: 停止条件设置不当

**解决**:
```dart
// 错误
stopCondition: (result) => false; // 永远不停止

// 正确
stopCondition: (result) {
  if (result.hasError) return true;
  if (result.attemptNumber > 100) return true; // 添加最大尝试次数保护
  return result.data?.isFinished ?? false;
}
```

### 问题2: 内存泄漏

**原因**: 未正确清理轮询

**解决**:
```dart
// 在dispose中清理
@override
void dispose() {
  _pollingManager.stopAll();
  _polling?.stop();
  super.dispose();
}
```

### 问题3: 请求频率过高

**原因**: 轮询间隔设置过短

**解决**:
```dart
// 使用智能轮询（指数退避）
PollingConfig.smart(
  initialIntervalMs: 1000,   // 开始1秒
  maxBackoffIntervalMs: 30000, // 最大30秒
)
```

### 问题4: 后端任务状态丢失

**原因**: 使用内存存储，服务重启后丢失

**解决**:
```java
// 生产环境使用Redis或数据库
@Service
public class RedisPollingTaskService implements PollingTaskService {
    private final ReactiveRedisTemplate redisTemplate;
    // ...
}
```

### 问题5: 长轮询超时

**原因**: 超时时间设置过短

**解决**:
```java
// 后端设置合理的超时
@PostMapping("/tasks/long-poll")
public Mono<PollingTaskStatusDto> longPollTaskStatus(
    @RequestBody LongPollingRequest request
) {
    int timeout = Math.min(request.getTimeoutSeconds(), 60); // 最大60秒
    return pollingTaskService.longPollTaskStatus(..., Duration.ofSeconds(timeout));
}
```

## 总结

API轮询功能提供了可靠的异步任务监控方案：

✅ **通用性强**: 适用于各种异步任务场景  
✅ **易于集成**: 简洁的API设计  
✅ **高效节能**: 智能轮询策略减少请求  
✅ **容错性好**: 完善的错误处理  
✅ **可扩展**: 支持长轮询、SSE降级等优化

建议在项目中优先使用SSE实现实时推送，将轮询作为可靠的降级方案。
