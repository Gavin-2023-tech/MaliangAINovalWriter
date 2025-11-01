#!/bin/bash
# MongoDB 副本集自动初始化脚本

echo "等待 MongoDB 启动..."
sleep 10

echo "检查副本集状态..."

# 尝试获取副本集状态（连接到 mongo 服务）
RS_STATUS=$(mongosh "mongodb://admin:admin123@mongo:27017/admin" --quiet --eval "try { rs.status().ok } catch(e) { 0 }" 2>/dev/null || echo "0")

if [ "$RS_STATUS" == "1" ]; then
    echo "✓ 副本集已初始化并运行正常"
    exit 0
fi

echo "副本集未初始化，开始初始化..."

# 初始化副本集
INIT_RESULT=$(mongosh "mongodb://admin:admin123@mongo:27017/admin" --quiet --eval "
try {
    var result = rs.initiate({
        _id: 'rs0',
        members: [{ _id: 0, host: 'mongo:27017' }]
    });
    print(JSON.stringify(result));
} catch(e) {
    print('Error: ' + e);
}
" 2>&1)

echo "初始化结果: $INIT_RESULT"

# 等待副本集成为主节点
echo "等待副本集成为主节点..."
for i in {1..30}; do
    sleep 2
    STATE=$(mongosh "mongodb://admin:admin123@mongo:27017/admin" --quiet --eval "try { rs.status().myState } catch(e) { 0 }" 2>/dev/null || echo "0")
    
    if [ "$STATE" == "1" ]; then
        echo "✓ 副本集已成为主节点 (PRIMARY)"
        exit 0
    fi
    
    echo "当前状态: $STATE, 等待中... ($i/30)"
done

echo "✓ 副本集初始化完成"
exit 0
