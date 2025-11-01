# API轮询功能设计文档

## 概述

本文档描述了 AINovalWriter 项目中通用的API轮询功能设计，包括前端（Flutter）和后端（Spring Boot）的实现方案。

## 设计目标

1. **通用性**：提供可复用的轮询服务，适用于各种异步任务场景
2. **灵活性**：支持短轮询、长轮询、智能轮询等多种模式
3. **高效性**：使用指数退避策略，减少不必要的请求
4. **可靠性**：支持错误重试、超时控制、取消机制
5. **易用性**：简洁的API设计，方便集成和使用

## 架构设计

```
┌─────────────────┐         轮询请求          ┌──────────────────┐
│                 │ ─────────────────────────> │                  │
│  Flutter前端    │                            │  Spring Boot后端 │
│  PollingService │ <───────────────────────── │  PollingController│
│                 │         状态响应            │                  │
└─────────────────┘                            └──────────────────┘
        │                                               │
        │                                               │
        v                                               v
┌─────────────────┐                            ┌──────────────────┐
│  PollingManager │                            │ PollingTaskService│
│  (管理多个轮询)  │                            │  (任务状态管理)   │
└─────────────────┘                            └──────────────────┘
```

## 前端实现（Flutter）

### 核心组件

#### 1. PollingConfig - 轮询配置类

提供灵活的轮询配置选项：

```dart
// 快速轮询（1秒）
final config = PollingConfig.fast(maxAttempts: 60);

// 标准轮询（3秒）
final config = PollingConfig.standard(timeoutMs: 300000);

// 智能轮询（指数退避）
final config = PollingConfig.smart(
  initialIntervalMs: 1000,
  maxAttempts: 100,
);

// 自定义配置
final config = PollingConfig(
  intervalMs: 5000,
  maxAttempts: 50,
  timeoutMs: 600000,
  useExponentialBackoff: true,
  maxBackoffIntervalMs: 30000,
  continueOnError: true,
  maxConsecutiveErrors: 3,
);
```

#### 2. PollingService - 轮询服务类

核心轮询服务，支持两种使用方式：

**方式一：Future模式（等待完成）**

```dart
final polling = PollingService<ImportStatus>();

final result = await polling.start(
  fetcher: () => apiClient.get('/import/$jobId/status'),
  parser: (data) => ImportStatus.fromJson(data),
  stopCondition: (result) {
    if (result.hasError) return true;
    if (result.data?.status == 'completed') return true;
    if (result.data?.status == 'failed') return true;
    return false;
  },
  config: PollingConfig.smart(maxAttempts: 100),
  onUpdate: (result) {
    print('Progress: ${result.data?.progress}%');
  },
  onComplete: (result) {
    print('Import completed!');
  },
  onError: (error) {
    print('Error: $error');
  },
);
```

**方式二：Stream模式（实时监听）**

```dart
final polling = PollingService<TaskStatus>();

polling.startStream(
  fetcher: () => apiClient.post('/polling/tasks/$taskId/status'),
  parser: (data) => TaskStatus.fromJson(data),
  stopCondition: (result) => result.data?.isFinished ?? false,
  config: PollingConfig.standard(timeoutMs: 300000),
).listen(
  (result) {
    if (result.hasData) {
      print('Status: ${result.data!.status}');
      print('Progress: ${result.data!.progress}%');
    }
  },
  onError: (error) {
    print('Error: $error');
  },
  onDone: () {
    print('Polling completed');
  },
);
```

#### 3. PollingManager - 轮询管理器

管理多个轮询任务的全局单例：

```dart
final manager = PollingManager();

// 启动轮询
await manager.startPolling<ImportStatus>(
  id: 'import_$jobId',
  fetcher: () => apiClient.get('/import/$jobId/status'),
  parser: (data) => ImportStatus.fromJson(data),
  stopCondition: (result) => result.data?.isCompleted ?? false,
  config: PollingConfig.smart(),
  onUpdate: (result) {
    // 更新UI
  },
);

// 停止特定轮询
manager.stopPolling('import_$jobId');

// 停止所有轮询
manager.stopAll();

// 获取统计信息
final stats = manager.getAllStatistics();
print('活跃轮询数: ${manager.activeCount}');
```

### 关键特性

#### 1. 智能轮询间隔（指数退避）

```dart
// 初始间隔：1秒
// 第2次：1.5秒
// 第3次：2.25秒
// 第4次：3.375秒
// ...
// 最大间隔：30秒

final config = PollingConfig.smart(
  initialIntervalMs: 1000,
  maxAttempts: 100,
);
```

#### 2. 停止条件

```dart
stopCondition: (result) {
  // 根据响应数据判断是否停止
  if (result.hasError) return true;
  
  final data = result.data;
  if (data == null) return false;
  
  // 任务完成
  if (data.status == 'completed' || data.status == 'failed') {
    return true;
  }
  
  // 进度达到100%
  if (data.progress >= 100) {
    return true;
  }
  
  return false;
}
```

#### 3. 错误处理

```dart
final config = PollingConfig(
  intervalMs: 3000,
  continueOnError: true,       // 出错时继续轮询
  maxConsecutiveErrors: 5,     // 最大连续错误次数
);
```

## 后端实现（Spring Boot）

### 核心组件

#### 1. PollingTaskStatusDto - 任务状态DTO

```java
@Data
@Builder
public class PollingTaskStatusDto {
    private String taskId;
    private String taskType;
    private String status;        // PENDING, RUNNING, COMPLETED, FAILED, CANCELLED
    private Integer progress;     // 0-100
    private String message;
    private Object result;
    private String error;
    private Instant createdAt;
    private Instant startedAt;
    private Instant finishedAt;
    private Long estimatedRemainingSeconds;
    private Map<String, Object> metadata;
    
    public boolean isFinished();
    public boolean isCompleted();
    public boolean isFailed();
}
```

#### 2. PollingTaskService - 轮询任务服务

```java
@Service
public class PollingTaskServiceImpl implements PollingTaskService {
    
    // 创建任务
    public String createTask(String taskType, Map<String, Object> metadata) {
        String taskId = UUID.randomUUID().toString();
        // 初始化任务状态
        return taskId;
    }
    
    // 获取任务状态（短轮询）
    public Mono<PollingTaskStatusDto> getTaskStatus(String taskId) {
        // 返回当前任务状态
    }
    
    // 长轮询
    public Mono<PollingTaskStatusDto> longPollTaskStatus(
        String taskId, 
        String lastVersion, 
        Duration timeout
    ) {
        // 等待状态变化或超时
    }
    
    // 更新任务状态
    public void updateTaskStatus(String taskId, String status, Integer progress, String message) {
        // 更新并触发长轮询返回
    }
    
    // 取消任务
    public Mono<Boolean> cancelTask(String taskId) {
        // 取消正在运行的任务
    }
}
```

#### 3. PollingController - 轮询控制器

```java
@RestController
@RequestMapping("/api/v1/polling")
public class PollingController {
    
    // 短轮询接口
    @PostMapping("/tasks/{taskId}/status")
    public Mono<PollingTaskStatusDto> getTaskStatus(@PathVariable String taskId) {
        return pollingTaskService.getTaskStatus(taskId);
    }
    
    // 长轮询接口
    @PostMapping("/tasks/long-poll")
    public Mono<PollingTaskStatusDto> longPollTaskStatus(
        @RequestBody LongPollingRequest request
    ) {
        return pollingTaskService.longPollTaskStatus(
            request.getTaskId(),
            request.getLastVersion(),
            Duration.ofSeconds(request.getTimeoutSeconds())
        );
    }
    
    // 取消任务
    @PostMapping("/tasks/{taskId}/cancel")
    public Mono<Boolean> cancelTask(@PathVariable String taskId) {
        return pollingTaskService.cancelTask(taskId);
    }
}
```

### 长轮询实现原理

```java
private Mono<PollingTaskStatusDto> pollWithRetry(
    String taskId, 
    String lastVersion, 
    Instant deadline
) {
    return Mono.defer(() -> {
        // 检查超时
        if (Instant.now().isAfter(deadline)) {
            return getTaskStatus(taskId);
        }
        
        String currentVersion = taskVersionMap.get(taskId);
        PollingTaskStatusDto status = taskStatusMap.get(taskId);
        
        // 状态已变化或任务完成，立即返回
        if (!currentVersion.equals(lastVersion) || status.isFinished()) {
            return Mono.just(status);
        }
        
        // 等待后重试
        return Mono.delay(Duration.ofMillis(500))
                .flatMap(tick -> pollWithRetry(taskId, lastVersion, deadline));
    });
}
```

## 使用场景

### 场景1：小说导入进度监控

```dart
// 开始导入
final jobId = await novelRepository.confirmAndStartImport(...);

// 轮询监控进度
final manager = PollingManager();
await manager.startPolling<ImportStatus>(
  id: 'import_$jobId',
  fetcher: () => apiClient.get('/novels/import/$jobId/status'),
  parser: (data) => ImportStatus.fromJson(data),
  stopCondition: (result) {
    final status = result.data?.status;
    return status == 'completed' || status == 'failed';
  },
  config: PollingConfig.smart(
    initialIntervalMs: 1000,
    maxAttempts: 300,  // 最多轮询5分钟
  ),
  onUpdate: (result) {
    // 更新进度条
    setState(() {
      progress = result.data?.progress ?? 0;
      message = result.data?.message ?? '';
    });
  },
  onComplete: (result) {
    if (result.data?.status == 'completed') {
      // 导入完成，刷新小说列表
      context.read<NovelListBloc>().add(RefreshNovels());
    } else {
      // 导入失败，显示错误
      showError(result.data?.error);
    }
  },
);
```

### 场景2：AI生成任务监控

```dart
// 启动AI生成任务
final taskId = await aiService.startGenerateScene(...);

// 监控生成进度
final polling = PollingService<AITaskStatus>();
polling.startStream(
  fetcher: () => apiClient.post('/polling/tasks/$taskId/status'),
  parser: (data) => AITaskStatus.fromJson(data),
  stopCondition: (result) => result.data?.isFinished ?? false,
  config: PollingConfig.standard(timeoutMs: 600000),
).listen(
  (result) {
    if (result.hasData) {
      final task = result.data!;
      
      // 更新UI
      setState(() {
        taskStatus = task.status;
        taskProgress = task.progress;
        taskMessage = task.message;
      });
      
      // 任务完成
      if (task.isCompleted && task.result != null) {
        final generatedContent = task.result['content'];
        // 处理生成的内容
      }
    }
  },
  onError: (error) {
    showError('生成失败: $error');
  },
);
```

### 场景3：后端异步任务处理

```java
@Service
public class NovelImportService {
    
    @Autowired
    private PollingTaskServiceImpl pollingTaskService;
    
    public String startImport(ImportRequest request) {
        // 创建任务
        String taskId = pollingTaskService.createTask(
            "NOVEL_IMPORT",
            Map.of("fileName", request.getFileName())
        );
        
        // 异步执行导入
        CompletableFuture.runAsync(() -> {
            try {
                // 更新为运行中
                pollingTaskService.updateTaskStatus(
                    taskId, "RUNNING", 0, "开始导入..."
                );
                
                // 执行导入逻辑
                for (int i = 0; i < 100; i++) {
                    // 处理每个章节
                    processChapter(i);
                    
                    // 更新进度
                    pollingTaskService.updateTaskStatus(
                        taskId, "RUNNING", i, "正在导入第" + i + "章"
                    );
                }
                
                // 完成
                pollingTaskService.updateTaskStatus(
                    taskId, "COMPLETED", 100, "导入完成"
                );
                pollingTaskService.updateTaskResult(taskId, importResult);
                
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

## 最佳实践

### 1. 选择合适的轮询策略

- **快速任务（< 10秒）**：使用快速轮询（1秒间隔）
- **中等任务（10秒 - 5分钟）**：使用标准轮询（3秒间隔）
- **长时任务（> 5分钟）**：使用智能轮询（指数退避）
- **实时性要求高**：优先使用SSE，轮询作为降级方案

### 2. 设置合理的超时时间

```dart
// 根据任务预期时长设置超时
final config = PollingConfig(
  intervalMs: 3000,
  timeoutMs: 300000,  // 5分钟超时
  maxAttempts: 100,   // 或限制最大尝试次数
);
```

### 3. 处理错误和边界情况

```dart
stopCondition: (result) {
  // 1. 检查错误
  if (result.hasError) {
    showError(result.error!);
    return true;
  }
  
  // 2. 检查数据有效性
  if (result.data == null) {
    return false;
  }
  
  // 3. 检查业务状态
  final status = result.data!.status;
  if (status == 'completed' || status == 'failed' || status == 'cancelled') {
    return true;
  }
  
  return false;
}
```

### 4. 资源清理

```dart
class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _pollingManager = PollingManager();
  
  @override
  void initState() {
    super.initState();
    _startPolling();
  }
  
  @override
  void dispose() {
    // 清理资源
    _pollingManager.stopAll();
    super.dispose();
  }
  
  void _startPolling() {
    _pollingManager.startPolling(
      id: 'my_task',
      // ...
    );
  }
}
```

### 5. 使用长轮询优化

```dart
// 前端：使用长轮询减少请求次数
final response = await apiClient.post('/polling/tasks/long-poll', data: {
  'taskId': taskId,
  'lastVersion': lastVersion,
  'timeoutSeconds': 30,
  'onlyOnChange': true,
});

// 后端：支持长轮询
@PostMapping("/tasks/long-poll")
public Mono<PollingTaskStatusDto> longPollTaskStatus(
    @RequestBody LongPollingRequest request
) {
    // 等待状态变化或超时
    return pollingTaskService.longPollTaskStatus(
        request.getTaskId(),
        request.getLastVersion(),
        Duration.ofSeconds(request.getTimeoutSeconds())
    );
}
```

## 性能优化

### 1. 指数退避策略

```dart
// 初始间隔短，逐渐增加
final config = PollingConfig.smart(
  initialIntervalMs: 1000,      // 开始1秒
  maxBackoffIntervalMs: 30000,  // 最大30秒
  backoffMultiplier: 1.5,       // 每次增加50%
);
```

### 2. 限制并发轮询数量

```dart
class PollingManager {
  static const int MAX_CONCURRENT_POLLS = 10;
  
  Future<PollingResult<T>?> startPolling<T>(...) async {
    if (activeCount >= MAX_CONCURRENT_POLLS) {
      throw StateError('超过最大并发轮询数量');
    }
    // ...
  }
}
```

### 3. 后端任务清理

```java
@Scheduled(fixedRate = 3600000)  // 每小时
public void cleanupOldTasks() {
    int cleaned = pollingTaskService.cleanupFinishedTasks();
    log.info("清理已完成的任务: {}", cleaned);
}
```

## 监控和调试

### 前端统计

```dart
// 获取轮询统计信息
final stats = pollingService.getStatistics();
print('当前状态: ${stats['isActive']}');
print('尝试次数: ${stats['attemptCount']}');
print('连续错误: ${stats['consecutiveErrors']}');
print('当前间隔: ${stats['currentIntervalMs']}ms');
print('已运行时长: ${stats['elapsedSeconds']}秒');

// 获取所有轮询统计
final allStats = PollingManager().getAllStatistics();
print('活跃轮询数: ${PollingManager().activeCount}');
```

### 后端日志

```java
@Slf4j
@Service
public class PollingTaskServiceImpl {
    
    @Override
    public Mono<PollingTaskStatusDto> getTaskStatus(String taskId) {
        log.debug("获取任务状态: taskId={}", taskId);
        // ...
    }
    
    @Override
    public Mono<PollingTaskStatusDto> longPollTaskStatus(...) {
        log.debug("长轮询: taskId={}, lastVersion={}, timeout={}ms", ...);
        // ...
    }
}
```

## 与SSE的对比

| 特性 | SSE | 短轮询 | 长轮询 |
|------|-----|--------|--------|
| 实时性 | 高 | 低-中 | 中 |
| 服务器资源 | 中 | 低 | 高 |
| 客户端资源 | 低 | 中 | 低 |
| 网络流量 | 低 | 高 | 中 |
| 适用场景 | 实时推送 | 简单查询 | 状态等待 |
| 兼容性 | 好 | 最好 | 好 |

**推荐策略**：
- 优先使用 SSE 实现实时推送
- 使用智能轮询作为降级方案
- 简单的状态查询使用短轮询
- 状态等待场景使用长轮询

## 总结

本API轮询功能设计提供了：

1. ✅ **通用的轮询服务**：适用于各种异步任务场景
2. ✅ **灵活的配置选项**：支持多种轮询策略
3. ✅ **智能的退避策略**：自动优化轮询频率
4. ✅ **完善的错误处理**：支持重试和降级
5. ✅ **简洁的API设计**：易于集成和使用
6. ✅ **长轮询优化**：减少不必要的请求
7. ✅ **全局任务管理**：统一管理多个轮询任务

通过合理使用本轮询功能，可以有效监控异步任务状态，提升用户体验。
