package com.ainovel.server.web.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.Map;

/**
 * 轮询任务状态DTO
 * 用于返回任务的当前状态信息
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class PollingTaskStatusDto {
    /**
     * 任务ID
     */
    private String taskId;

    /**
     * 任务类型
     */
    private String taskType;

    /**
     * 任务状态: PENDING, RUNNING, COMPLETED, FAILED, CANCELLED
     */
    private String status;

    /**
     * 进度百分比 (0-100)
     */
    private Integer progress;

    /**
     * 状态消息
     */
    private String message;

    /**
     * 任务结果（仅在COMPLETED状态时返回）
     */
    private Object result;

    /**
     * 错误信息（仅在FAILED状态时返回）
     */
    private String error;

    /**
     * 错误详情（仅在FAILED状态时返回）
     */
    private String errorDetail;

    /**
     * 任务创建时间
     */
    private Instant createdAt;

    /**
     * 任务开始时间
     */
    private Instant startedAt;

    /**
     * 任务完成/失败时间
     */
    private Instant finishedAt;

    /**
     * 预估剩余时间（秒）
     */
    private Long estimatedRemainingSeconds;

    /**
     * 扩展数据
     */
    private Map<String, Object> metadata;

    /**
     * 是否完成（包括成功和失败）
     */
    public boolean isFinished() {
        return "COMPLETED".equals(status) || "FAILED".equals(status) || "CANCELLED".equals(status);
    }

    /**
     * 是否成功完成
     */
    public boolean isCompleted() {
        return "COMPLETED".equals(status);
    }

    /**
     * 是否失败
     */
    public boolean isFailed() {
        return "FAILED".equals(status);
    }

    /**
     * 是否取消
     */
    public boolean isCancelled() {
        return "CANCELLED".equals(status);
    }

    /**
     * 是否正在运行
     */
    public boolean isRunning() {
        return "RUNNING".equals(status) || "PENDING".equals(status);
    }
}
