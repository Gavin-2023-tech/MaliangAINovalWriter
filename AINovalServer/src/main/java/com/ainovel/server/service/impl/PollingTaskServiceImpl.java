package com.ainovel.server.service.impl;

import com.ainovel.server.service.PollingTaskService;
import com.ainovel.server.web.dto.PollingTaskStatusDto;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 轮询任务服务实现
 * 提供基于内存的任务状态管理和长轮询支持
 */
@Slf4j
@Service
public class PollingTaskServiceImpl implements PollingTaskService {

    /**
     * 任务状态存储（生产环境应使用Redis或数据库）
     */
    private final Map<String, PollingTaskStatusDto> taskStatusMap = new ConcurrentHashMap<>();

    /**
     * 任务版本号（用于检测状态变化）
     */
    private final Map<String, String> taskVersionMap = new ConcurrentHashMap<>();

    @Override
    public Mono<PollingTaskStatusDto> getTaskStatus(String taskId) {
        log.debug("获取任务状态: taskId={}", taskId);
        
        PollingTaskStatusDto status = taskStatusMap.get(taskId);
        if (status == null) {
            log.warn("任务不存在: taskId={}", taskId);
            return Mono.error(new IllegalArgumentException("任务不存在: " + taskId));
        }

        return Mono.just(status);
    }

    @Override
    public Mono<PollingTaskStatusDto> longPollTaskStatus(String taskId, String lastVersion, Duration timeout) {
        log.debug("长轮询任务状态: taskId={}, lastVersion={}, timeout={}ms", 
                  taskId, lastVersion, timeout.toMillis());

        // 检查任务是否存在
        if (!taskStatusMap.containsKey(taskId)) {
            return Mono.error(new IllegalArgumentException("任务不存在: " + taskId));
        }

        Instant deadline = Instant.now().plus(timeout);
        
        return Mono.defer(() -> pollWithRetry(taskId, lastVersion, deadline))
                .timeout(timeout)
                .onErrorResume(e -> {
                    log.debug("长轮询超时或出错: taskId={}, error={}", taskId, e.getMessage());
                    // 超时时返回当前状态
                    return getTaskStatus(taskId);
                });
    }

    /**
     * 轮询重试逻辑
     */
    private Mono<PollingTaskStatusDto> pollWithRetry(String taskId, String lastVersion, Instant deadline) {
        return Mono.defer(() -> {
            // 检查是否超时
            if (Instant.now().isAfter(deadline)) {
                return getTaskStatus(taskId);
            }

            String currentVersion = taskVersionMap.get(taskId);
            PollingTaskStatusDto status = taskStatusMap.get(taskId);

            // 如果版本号不同或任务已完成，立即返回
            if (status != null && (!currentVersion.equals(lastVersion) || status.isFinished())) {
                log.debug("任务状态已变化: taskId={}, oldVersion={}, newVersion={}, status={}", 
                          taskId, lastVersion, currentVersion, status.getStatus());
                return Mono.just(status);
            }

            // 否则等待一段时间后重试
            return Mono.delay(Duration.ofMillis(500))
                    .flatMap(tick -> pollWithRetry(taskId, lastVersion, deadline));
        });
    }

    @Override
    public Mono<Boolean> cancelTask(String taskId) {
        log.info("取消任务: taskId={}", taskId);
        
        PollingTaskStatusDto status = taskStatusMap.get(taskId);
        if (status == null) {
            return Mono.just(false);
        }

        // 如果任务已完成，不能取消
        if (status.isFinished()) {
            log.warn("任务已完成，无法取消: taskId={}, status={}", taskId, status.getStatus());
            return Mono.just(false);
        }

        // 更新状态为已取消
        status.setStatus("CANCELLED");
        status.setFinishedAt(Instant.now());
        updateTaskVersion(taskId);

        return Mono.just(true);
    }

    @Override
    public Mono<Boolean> taskExists(String taskId) {
        return Mono.just(taskStatusMap.containsKey(taskId));
    }

    @Override
    public Mono<Boolean> cleanupTask(String taskId) {
        log.debug("清理任务: taskId={}", taskId);
        
        PollingTaskStatusDto removed = taskStatusMap.remove(taskId);
        taskVersionMap.remove(taskId);
        
        return Mono.just(removed != null);
    }

    /**
     * 创建新任务（供其他服务调用）
     */
    public String createTask(String taskType, Map<String, Object> metadata) {
        String taskId = UUID.randomUUID().toString();
        
        PollingTaskStatusDto status = PollingTaskStatusDto.builder()
                .taskId(taskId)
                .taskType(taskType)
                .status("PENDING")
                .progress(0)
                .message("任务已创建")
                .createdAt(Instant.now())
                .metadata(metadata)
                .build();

        taskStatusMap.put(taskId, status);
        updateTaskVersion(taskId);

        log.info("创建任务: taskId={}, taskType={}", taskId, taskType);
        return taskId;
    }

    /**
     * 更新任务状态（供其他服务调用）
     */
    public void updateTaskStatus(String taskId, String status, Integer progress, String message) {
        PollingTaskStatusDto taskStatus = taskStatusMap.get(taskId);
        if (taskStatus == null) {
            log.warn("尝试更新不存在的任务: taskId={}", taskId);
            return;
        }

        taskStatus.setStatus(status);
        taskStatus.setProgress(progress);
        taskStatus.setMessage(message);

        if ("RUNNING".equals(status) && taskStatus.getStartedAt() == null) {
            taskStatus.setStartedAt(Instant.now());
        }

        if (taskStatus.isFinished() && taskStatus.getFinishedAt() == null) {
            taskStatus.setFinishedAt(Instant.now());
        }

        updateTaskVersion(taskId);
        log.debug("更新任务状态: taskId={}, status={}, progress={}", taskId, status, progress);
    }

    /**
     * 更新任务结果（供其他服务调用）
     */
    public void updateTaskResult(String taskId, Object result) {
        PollingTaskStatusDto taskStatus = taskStatusMap.get(taskId);
        if (taskStatus != null) {
            taskStatus.setResult(result);
            updateTaskVersion(taskId);
        }
    }

    /**
     * 更新任务错误（供其他服务调用）
     */
    public void updateTaskError(String taskId, String error, String errorDetail) {
        PollingTaskStatusDto taskStatus = taskStatusMap.get(taskId);
        if (taskStatus != null) {
            taskStatus.setStatus("FAILED");
            taskStatus.setError(error);
            taskStatus.setErrorDetail(errorDetail);
            taskStatus.setFinishedAt(Instant.now());
            updateTaskVersion(taskId);
        }
    }

    /**
     * 更新任务版本号
     */
    private void updateTaskVersion(String taskId) {
        taskVersionMap.put(taskId, UUID.randomUUID().toString());
    }

    /**
     * 获取任务版本号
     */
    public String getTaskVersion(String taskId) {
        return taskVersionMap.getOrDefault(taskId, "");
    }

    /**
     * 获取所有活跃任务数量
     */
    public int getActiveTaskCount() {
        return (int) taskStatusMap.values().stream()
                .filter(status -> !status.isFinished())
                .count();
    }

    /**
     * 清理所有已完成的任务
     */
    public int cleanupFinishedTasks() {
        int count = 0;
        for (Map.Entry<String, PollingTaskStatusDto> entry : taskStatusMap.entrySet()) {
            if (entry.getValue().isFinished()) {
                taskStatusMap.remove(entry.getKey());
                taskVersionMap.remove(entry.getKey());
                count++;
            }
        }
        log.info("清理已完成的任务: count={}", count);
        return count;
    }
}
