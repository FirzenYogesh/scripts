import os
import sys
import subprocess

# Function to extract a clip with two-stage processing (fast first, fallback if needed)
def extract_clip(video_path, start_time, clip_duration, output_file):
    """
    Extracts a clip using stream copy first. If sync issues are detected, retries with audio re-encoding.
    """

    # Step 1: Try fast extraction (copy both video & audio)
    ffmpeg_cmd_fast = [
        "ffmpeg",
        "-i", video_path,
        "-ss", seconds_to_time(start_time),
        "-t", str(clip_duration),
        "-map", "0:v", "-map", "0:a:0",
        "-c:v", "copy",
        "-c:a", "copy",
        "-reset_timestamps", "1",
        "-avoid_negative_ts", "make_zero",
        "-y",
        output_file
    ]

    print(f"Trying fast extraction: {output_file}")
    result = subprocess.run(ffmpeg_cmd_fast, capture_output=True, text=True)

    # Step 2: If sync issues occur, retry with audio re-encoding
    if result.returncode != 0 or "PTS" in result.stderr:
        print(f"Detected sync issue in {output_file}, re-processing with audio re-encoding...")

        ffmpeg_cmd_fallback = [
            "ffmpeg",
            "-i", video_path,
            "-ss", seconds_to_time(start_time),
            "-t", str(clip_duration),
            "-map", "0:v", "-map", "0:a:0",
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "192k",
            "-reset_timestamps", "1",
            "-avoid_negative_ts", "make_zero",
            "-y",
            output_file
        ]

        subprocess.run(ffmpeg_cmd_fallback)

# Check if parent folder is provided
if len(sys.argv) < 2:
    print("Usage: python extract_clips.py <parent_folder>")
    sys.exit(1)

parent_folder = sys.argv[1]

# Ensure output folders exist
output_folder = os.path.join(parent_folder, "clips")
merged_folder = os.path.join(parent_folder, "merged_videos")
os.makedirs(output_folder, exist_ok=True)
os.makedirs(merged_folder, exist_ok=True)

# Function to convert timestamp to seconds
def time_to_seconds(timestamp):
    h, m, s = map(int, timestamp.split(":"))
    return h * 3600 + m * 60 + s

# Function to convert seconds to timestamp
def seconds_to_time(seconds):
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    return f"{h:02}:{m:02}:{s:02}"

# Find all video files in the parent folder
video_files = [f for f in os.listdir(parent_folder) if f.endswith((".mp4", ".mkv", ".mov"))]

if not video_files:
    print("No video files found in the folder.")
    sys.exit(1)

# Process each video file
for video_file in video_files:
    video_path = os.path.join(parent_folder, video_file)
    video_name = os.path.splitext(video_file)[0]
    chapter_file = os.path.join(parent_folder, f"{video_name}_chapters.txt")

    # Check if the corresponding chapter file exists
    if not os.path.exists(chapter_file):
        print(f"Skipping {video_file}: No chapter file found ({video_name}_chapters.txt)")
        continue

    print(f"Processing {video_file} with {chapter_file}")

    # Read chapter markers
    with open(chapter_file, "r") as f:
        lines = [line.strip().split(" - ") for line in f.readlines() if " - " in line]

    # Convert timestamps to seconds and sort them
    timestamps = [(time_to_seconds(line[0]), line[1]) for line in lines]
    timestamps.sort()

    # Merge overlapping timestamps
    merged_intervals = []
    current_start = max(0, timestamps[0][0] - 60)  # Start 60 sec before first timestamp
    current_end = timestamps[0][0]  # Default end time is first timestamp
    current_desc = timestamps[0][1]  # Description for naming

    for i in range(1, len(timestamps)):
        ts, desc = timestamps[i]

        # If the timestamp overlaps with the previous (within the same range)
        if ts <= current_end + 60:  # Overlapping or within buffer range
            current_end = max(current_end, ts)  # Extend the end time
        else:
            # Store the previous range
            merged_intervals.append((current_start, current_end + 60, current_desc))
            # Start a new range
            current_start = max(0, ts - 60)
            current_end = ts
            current_desc = desc

    # Add the last range
    merged_intervals.append((current_start, current_end + 60, current_desc))

    # Process each merged clip with FFmpeg
    clip_files = []
    for index, (start_time, end_time, description) in enumerate(merged_intervals):
        clip_duration = end_time - start_time
        output_file = os.path.join(output_folder, f"{video_name}_{index+1}_{description.replace(' ', '_')}.mp4")
        clip_files.append(output_file)
        extract_clip(video_path, start_time, clip_duration, output_file)

        # # FFmpeg command
        # ffmpeg_cmd = [
        #     "ffmpeg",
        #     "-i", video_path,
        #     "-ss", seconds_to_time(start_time),
        #     "-t", str(clip_duration),
        #     "-map", "0:v", "-map", "0:a:0",
        #     "-c:v", "copy",
        #     "-c:a", "copy",  # Use stream copy for audio
        #     "-reset_timestamps", "1",
        #     "-avoid_negative_ts", "make_zero",
        #     "-y",
        #     output_file
        # ]


        # # Execute the command
        # subprocess.run(ffmpeg_cmd)

    print(f"Clips extracted successfully for {video_name}!")

    # ------------------ Merging Process ------------------

    # Maximum duration for merged videos (8 minutes = 480 seconds)
    MAX_VIDEO_DURATION = 480
    BUFFER_DURATION = 30  # Allow up to a max of 8:30 (510 seconds)
    current_batch = []
    current_duration = 0
    batch_number = 1

    # Read durations of clips
    clip_durations = {}
    for clip in clip_files:
        probe_cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", clip]
        duration = float(subprocess.run(probe_cmd, capture_output=True, text=True).stdout.strip())
        clip_durations[clip] = duration

    # Group clips into 8-minute videos (strict limit of 8:30)
    merged_batches = []
    for clip in clip_files:
        duration = clip_durations.get(clip, 0)

        if current_duration + duration > MAX_VIDEO_DURATION:
            # Check if we can fit within the buffer (exactly 8:30 max)
            if current_duration + duration <= MAX_VIDEO_DURATION + BUFFER_DURATION:
                current_batch.append(clip)  # Include this clip
                current_duration += duration
            else:
                # Save the current batch and start a new one
                if current_batch:
                    merged_batches.append(current_batch)
                current_batch = [clip]
                current_duration = duration
        else:
            current_batch.append(clip)
            current_duration += duration

    # **Final Optimization:** Merge small leftover clips into the last batch if possible
    if len(merged_batches) > 1:
        last_batch = merged_batches[-1]
        second_last_batch = merged_batches[-2]

        # If the last batch has only 1 or 2 clips, try merging it with the previous batch
        last_batch_duration = sum(clip_durations[clip] for clip in last_batch)
        second_last_batch_duration = sum(clip_durations[clip] for clip in second_last_batch)

        if last_batch_duration < 120 and second_last_batch_duration + last_batch_duration <= MAX_VIDEO_DURATION + BUFFER_DURATION:
            # Merge last batch into the second-last batch
            merged_batches[-2].extend(merged_batches[-1])
            merged_batches.pop()  # Remove the last batch since it's now merged

    # Merge clips in each batch
    for batch_index, batch in enumerate(merged_batches):
        merge_list_file = os.path.join(output_folder, "merge_list.txt")

        # Write batch clip paths to file for merging
        with open(merge_list_file, "w") as f:
            for clip in batch:
                f.write(f"file '{clip}'\n")

        merged_output = os.path.join(merged_folder, f"{video_name}_merged_{batch_index+1}.mp4")

        # FFmpeg command to merge
        merge_cmd = [
            "ffmpeg", "-f", "concat", "-safe", "0",
            "-i", merge_list_file, "-c", "copy",
            merged_output
        ]

        subprocess.run(merge_cmd)
        print(f"Merged video created: {merged_output}")

print("All videos processed successfully!")
