#!/bin/sh
max_acceptable_time_difference=2
root_dir=/mnt/dev1/record/
for entry in "$root_dir"*
do
	channel="$entry/"
	echo "checking $channel .."
#	for date in $(find $channel -type d | sort )
#	do
#		if [ "$date" = "$channel" ];then
#			echo "Passing next day!"
#			continue
#		fi
		last_segment_duration=0

		echo "checking $channel"
		for segment in $(find $channel -type f -name "*.mkv" | sort )
		do
			str=$(ffmpeg -i $segment -t 0.1 -f null - 2>&1 | grep Output -A 10 | grep DURATION | awk '{print $3}' | cut -d "." -f 1)
			h=$(echo $str | cut -d ":" -f 1 | awk '{print $1+0}')
			m=$(echo $str | cut -d ":" -f 2 | awk '{print $1+0}')
			s=$(echo $str | cut -d ":" -f 3 | awk '{print $1+0}')
			current_segment_duration=$((h*3600+m*60+s))
			current_segment_start_time=$(basename $segment | cut -d "." -f 1 | awk '{print $1+0}')
			if [ $last_segment_duration -gt 0 ];then
				expected_current_segment_start_time=$((last_segment_start_time+last_segment_duration))
				difference=$((current_segment_start_time-expected_current_segment_start_time))
				if [ $difference -ge $max_acceptable_time_difference ] || [ $difference -le $((-1*max_acceptable_time_difference)) ];then
					echo "$segment needs to start $difference seconds before/after than $current_segment_start_time"
				fi
				#if [ $difference -ne 0 ];then
				#	echo "expected : $expected_current_segment_start_time current : $current_segment_start_time difference : $difference"
				#fi
			fi
			
			last_segment_start_time=$current_segment_start_time
			last_segment_duration=$current_segment_duration
			
			
		done
	#done
done
