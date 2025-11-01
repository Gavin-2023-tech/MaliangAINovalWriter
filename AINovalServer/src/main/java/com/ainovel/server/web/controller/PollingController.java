package com.ainovel.server.web.controller;

import com.ainovel.server.service.PollingTaskService;
import com.ainovel.server.web.dto.LongPollingRequest;
import com.ainovel.server.web.dto.PollingTaskStatusDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.time.Duration;

/**
 * 轮询控制器
 * 提供任务状态轮询接口
 */
@Slf4j
@RestController
@RequestMapping("/api/v1/polling")
@RequiredArgsConstructor
public class PollingController {

    private final PollingTaskService pollingTaskService;

    /**
     * 获取任务状态（短轮询）
     * 
     * @param taskId 任务ID
     * @return 任务状态
     */
    @PostMapping("/tasks/{taskId}/status")
    public Mono<PollingTaskStatusDto> getTaskStatus(@PathVariable String taskId) {
        log.debug("短轮询获取任务状态: taskId={}", taskId);
        return pollingTaskService.getTaskStatus(taskId);
    }

    /**
     * 长轮询获取任务状态
     * 如果任务状态未变化，会等待直到状态变化或超时
     * 
     * @param request 长轮询请求
     * @return 任务状态
     */
    @PostMapping(value = "/tasks/long-poll", produces = MediaType.APPLICATION_JSON_VALUE)
    public Mono<PollingTaskStatusDto> longPollTaskStatus(@RequestBody LongPollingRequest request) {
        log.debug("长轮询任务状态: taskId={}, lastVersion={}, timeout={}s", 
                  request.getTaskId(), request.getLastVersion(), request.getTimeoutSeconds());

        // 限制超时时间，避免过长的连接
        int timeoutSeconds = Math.min(request.getTimeoutSeconds(), 60);
        Duration timeout = Duration.ofSeconds(timeoutSeconds);

        if (request.getOnlyOnChange() && request.getLastVersion() != null) {
            return pollingTaskService.longPollTaskStatus(
                    request.getTaskId(), 
                    request.getLastVersion(), 
                    timeout
            );
        } else {
            // 如果不要求状态变化，直接返回当前状态
            return pollingTaskService.getTaskStatus(request.getTaskId());
        }
    }

    /**
     * 取消任务
     * 
     * @param taskId 任务ID
     * @return 是否成功取消
     */
    @PostMapping("/tasks/{taskId}/cancel")
    public Mono<Boolean> cancelTask(@PathVariable String taskId) {
        log.info("取消任务: taskId={}", taskId);
        return pollingTaskService.cancelTask(taskId);
    }

    /**
     * 检查任务是否存在
     * 
     * @param taskId 任务ID
     * @return 是否存在
     */
    @PostMapping("/tasks/{taskId}/exists")
    public Mono<Boolean> taskExists(@PathVariable String taskId) {
        return pollingTaskService.taskExists(taskId);
    }

    /**
     * 清理已完成的任务
     * 
     * @param taskId 任务ID
     * @return 是否成功清理
     */
    @PostMapping("/tasks/{taskId}/cleanup")
    public Mono<Boolean> cleanupTask(@PathVariable String taskId) {
        log.debug("清理任务: taskId={}", taskId);
        return pollingTaskService.cleanupTask(taskId);
    }
}
