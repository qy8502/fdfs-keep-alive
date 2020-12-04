# fdfs-keep-alive
# fastdfs保活脚本

配置trackers和storages服务器地址检查状态。对于配置的storages，如果在多次上传实验中都没有轮询到，就意味着可能掉线或假死，就会重启。
