------- UPDATE -------

-- 01.00.0005
alter table `t_ipc_alarm_setting` add column `sound` int default 0;

-- 01.00.0013
alter table `t_channel` add column `video_source_index` int default 0;

-- 01.00.0014
alter table `t_channel` add column `algorithm_configuration_protocol` int default 0;

-- 01.00.0020
alter table `t_channel` add column `reverse_tilt` int default 1;
