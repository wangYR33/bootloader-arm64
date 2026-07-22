pragma foreign_keys = on; -- 开启外键

-- 通道
create table if not exists `t_channel` (
    `id`                        integer primary key autoincrement, -- 唯一ID
    `ch_num`                    int unique not null,  -- 通道号: 0, 1, 2, 3 ...
    `name`                      text not null, -- 自定义通道名称
    `activated`                 int,  -- 是否启用该通道
    `ip_address`                int,  -- onvif服务url http://xxx:xx/onvif/device_service
    `activated_stream_type`     int,  -- 启用码流类型 0 main | 1 sub
    `main_stream`               text, -- 主码流
    `sub_stream`                text, -- 子码流
    `multicast_address`         text, -- 组播拉流地址
    `auth_type`                 int,  -- 相机的认证方式 0 无 | 1 http摘要认证 | 2 ws-security认证
    `protocol`                  int,  -- 通道拉流协议 通道拉流协议 0 rtsp | 1 onvif
    `push_url`                  text, -- 推流目标地址
    `push_multicast_address`    text, -- 推流广播地址
    `push_net_type`             text, -- 推流网络类型:  0 TCP | 1 UDP | 2 udp_multicast(组播)
    `push_type`                 text, -- 推流类型:  0 不推 | 1 推到本地 | 2 推到第三方
    `net_type`                  int,  -- 网络类型: 0 TCP | 1 UDP | 2 udp_multicast
    `camera_name`               text, -- 相机名称
    `camera_type`               int,  -- 相机类型:  0 普通摄像机 | 1  球形摄像机
    `camera_manufacturer`       text, -- 相机制造商信息
    `account`                   text, -- 用户名
    `password`                  text, -- 密码
    `camera_location`           text, -- 相机地理位置: chengdu, beijing ...
    `ptz_protocol_type`         text, -- 相机云台控制协议 0 ptz | 1 pv | 2 ?
    `manual_recorded`           int,  -- 是否手动录像
    `record_mode`               int,  -- 是否只录关键帧
    `record_size`               int,  -- 该通道允许的录像最大体积, GB
    `format`                    text, -- 录像格式 flv, mp4 ...
    `record_root`               text, -- 每个通道都有自己的录像文件根目录
    `disk_id`                   int,  -- 挂载位置的磁盘ID
    `show_datetime`             int,  -- 是否显示时间
    `time_format`               int,  -- 时间格式:  0 24小时 | 1 12 小时, 11:14:15
    `date_format`               int,  -- 日期格式:  0 年月日, 2021-04-19 | 1 月日年, 19-04-2021 | 2 日月年, 04-19-2021
    `show_watermask`            int,  -- 是否显示水印
    `watermask`                 text,  -- 水印字段
    `video_source_index`        int,  -- video_source_index
    `algorithm_configuration_protocol` int,  -- algorithm_configuration_protocol
    `reverse_tilt` int -- reverse_tilt
);
create index if not exists index_t_channel_ch_num on t_channel (ch_num);

-- 抓图
create table if not exists `t_screenshot` (
    `id`            integer primary key autoincrement, -- 唯一ID
    `path`          text unique not null,  -- 文件路径
    `user_id`       int,   -- 用户ID
    `ch_num`        int,   -- 通道号
    `type`          int,   -- 抓图类型 0 预览抓图 | 1 录像抓图
    `timestamp`     int,   -- 时间戳
    `format`        int, -- 图片格式: 0 jpg | 1 png
    -- foreign key (`user_id`) references `t_user`(`id`) on delete cascade on update cascade,
    foreign key (`ch_num`) references `t_channel`(`ch_num`) on delete cascade on update cascade
);

-- 用户
create table if not exists `t_user` (
    `id`         integer primary key autoincrement, -- 唯一ID
    `account`    text unique not null,   -- 登录账户名
    `password`   text not null,   -- 登录密码
    `createtime` text not null,   -- 账户创建时间
    `level`      int not null     -- 权限级别
);

-- 巡游列表
create table if not exists `t_cruise` (
    `id`        integer primary key autoincrement, -- 唯一ID
    `name`      text,   -- 巡游名称
    `activated` text,   -- 0 | 1 是否启用
    `group`     text,   -- 通道组, 用于巡游切换, [1, 2, 3, 4]
    `interval`  int     -- 巡游切换间隔,  秒
);

-- 录像文件
create table if not exists `t_record` (
    `id`                integer primary key autoincrement, -- 唯一ID
    `ch_num`            int, -- 通道号
    `path`              text unique not null,   -- 文件路径
    `length`            int, -- 录像长度, 秒
    `date`              int, -- 日期, 19970102
    `manual`            int, -- 是否为手动录制
    `mode`              int, -- 录制模式
    `type`              int, -- 录像类型
    `start`             int, -- 开始录制的时间, 当天的秒数
    `key_frame_split`   int, -- I帧间隔
    `frame_rate`        int not null default 0, -- 帧率
    foreign key (`ch_num`) references `t_channel`(`ch_num`) on delete cascade on update cascade
);
create index if not exists index_t_record_path on t_record (path);

create table if not exists `t_metadata` (
    `id`                integer primary key autoincrement, -- 唯一ID
    `ch_num`            int, -- 通道号
    `path`              text unique not null,   -- 文件路径
    `length`            int, -- 录像长度, 秒
    `date`              int, -- 日期, 19970102
    `type`              int, -- 录像类型
    `start`             int, -- 开始录制的时间, 当天的秒数
    foreign key (`ch_num`) references `t_channel`(`ch_num`) on delete cascade on update cascade
);
create index if not exists index_t_metadata_path on t_metadata (path);

-- 网络信息
create table if not exists `t_net_msg` (
    `id` integer primary key autoincrement, -- 唯一ID
    `net_card`  text, -- 网卡名称
    `ip_v4`     text, -- ip_v4地址
    `netmask`   text, -- 子网掩码
    `gateway`   text, -- 网关地址
    `dns1`      text  -- dns地址
);

-- 录像计划
create table if not exists `t_record_plan` (
    `id`            integer primary key autoincrement, -- 唯一ID
    `ch_num`        int, -- 通道号
    `day_of_week`   int, -- 录制计划是周几生效: 1-7表示周一到周天
    `start`         int, -- 计划录制开始时的当天秒数
    `end`           int, -- 计划录制结束时的当天秒数
    `activated`     int, -- 录制计划是否激活
    foreign key (`ch_num`) references `t_channel`(`ch_num`) on delete cascade on update cascade
);

-- 通道分配
create table if not exists `t_channel_assign`(
    `id`        integer primary key autoincrement, -- 唯一标示
    `uid`       int, -- 用户ID
    `ch_num`    int, -- 通道号
    unique(`uid`, `ch_num`),
    foreign key (`uid`) references `t_user`(`id`) on delete cascade on update cascade,
    foreign key (`ch_num`) references `t_channel`(`ch_num`) on delete cascade on update cascade
);

-- 录像时间段保护
create table if not exists `t_record_protect` (
    `id`        integer primary key autoincrement, -- 唯一标示
    `start`     int, -- 保护时间段开始时间, 包含
    `end`       int, -- 保护时间段结束时间, 不包含
    `ch_num`    int, -- 通道号
    unique(`start`, `end`, `ch_num`),
    foreign key (`ch_num`) references `t_channel`(`ch_num`) on delete cascade on update cascade
);

-- 储存键值对
create table if not exists `t_global_value` (
    `id`        integer primary key autoincrement, -- 唯一标示
    `key`       text,
    `value`     text
);

-- 磁盘信息
create table if not exists `t_disk` (
    `id`    integer primary key autoincrement, -- 唯一标示
    `sign`  text, -- 磁盘号: a b c d ...
    `part`  int -- 磁盘分区标号
    -- unique(`sign`, `part`)
);

-- onvif告警事件类型(TOPIC)
create table if not exists `t_onvif_event_topic` (
    `id`    integer primary key autoincrement, -- 唯一标示
    `name`  text, -- TPOIC实际字符串
    unique(`name`)
);

-- onvif告警事件
create table if not exists `t_onvif_event` (
    `id`        integer primary key autoincrement, -- 唯一标示
    `ch_num`    int, -- 通道号
    `ip`        int, -- 该条通知所在的IP
    `sec_time`  int, -- 事件时间戳, 秒级
    `topic`     string, -- 事件类型TOPIC
    `source`    text, -- 处理事件的模块标示
    `data`      text -- 事件相关属性
);

-- 通道告警配置
create table if not exists `t_ipc_alarm_setting` (
    `id`                    integer primary key autoincrement, -- 唯一标示
    `ch_num`                int, -- 通道号
    `topic_type`            text, -- onvif告警类型
    `enable`                int, -- 是否启动告警通知
    `record`                int, -- 是否录像
    `pre_recording_time`    int, -- 预录时间, 秒
    `delay_recording_time`  int, -- 延录时间, 秒
    `sound`                 int, -- is alarm sound enable?
    unique(`ch_num`)
);

-- nvr通用文件记录
create table if not exists `t_nvr_file` (
    `id`                    integer primary key autoincrement, -- 唯一标示
    `name`                  text, -- 文件名 eg: 1.mp4
    `path`                  text, -- 文件路径 eg: /mnt/dev/record/1.mp4
    `type`                  text, -- 文件类型 eg: zip mp4
    `category`              text, -- 自定义分类, 便于检索
    `createtime`            text, -- 自定义分类, 便于检索
    `updatetime`            text, -- 文件或信息创建时间, 秒级时间戳
    `expiration_time`       text  -- 文件过期时间长度, 秒级时间戳, 真正的过期时间为 updatetime + expirationTime
);

create table if not exists `t_gnss` (
    `id`                    integer primary key autoincrement, -- 唯一标示
    `longitude`                 text, -- 经度
    `latitude`                  text, -- 纬度
    `time`                      text  -- 时间
);

create table if not exists `t_gyro` (
    `id`                    integer primary key autoincrement, -- 唯一标示
    `gyro_x`                double, -- x
    `gyro_y`                double, -- y
    `gyro_z`                double,  -- z
    `accel_x`               double, -- x
    `accel_y`               double, -- y
    `accel_z`               double,  -- z
    `time`                  text  -- 时间
);
