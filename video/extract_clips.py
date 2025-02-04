import os
import sys
import subprocess

OVERLAPPING_BUFFER_START = 120
OVERLAPPING_BUFFER_END = 60
    # Maximum duration for merged videos (8 minutes = 480 seconds)
MAX_VIDEO_DURATION = 480
BUFFER_DURATION = 30  # Allow up to a max of 8:30 (510 seconds)

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

def extract_timestamps(chapter_file):
    # Read chapter markers
    with open(chapter_file, "r") as f:
        lines = [line.strip().split(" - ") for line in f.readlines() if " - " in line]

    # Convert timestamps to seconds and sort them
    timestamps = [(time_to_seconds(line[0]), line[1]) for line in lines]
    timestamps.sort()
    return timestamps

def get_keyframes(video_path, duration_limit=1800):
    """
    Extracts keyframe timestamps from the first `duration_limit` seconds of the video.
    This speeds up scanning for large files.
    """
    print(f"Getting Keyframes for {video_path} with duration {duration_limit}")
    cmd = [
        "ffprobe", "-select_streams", "v",
        "-show_frames", "-show_entries", "frame=pkt_pts_time,pict_type",
        "-of", "csv",
        "-read_intervals", f"%+#{duration_limit}",  # Scan only first X seconds
        video_path
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    keyframes = []

    for line in result.stdout.split("\n"):
        parts = line.strip().split(",")
        if len(parts) == 2 and parts[1] == "I":  # I-Frame (Keyframe)
            try:
                keyframes.append(float(parts[0]))  # Store timestamp
            except ValueError:
                continue  # Skip invalid rows (e.g., headers)

    return keyframes


def get_nearest_keyframe(target_time, keyframes):
    """
    Finds the nearest keyframe before the target time.
    """
    print(f"Finding the nearest keyframe")
    keyframes_before_target = [k for k in keyframes if k <= target_time]

    if keyframes_before_target:
        nearest_keyframe = max(keyframes_before_target)  # Get the closest keyframe before target
    else:
        nearest_keyframe = target_time  # Default to original start if no keyframes exist

    # Force start time to be an even number
    if nearest_keyframe % 2 != 0:
        nearest_keyframe = nearest_keyframe - 1  # Round down to the nearest even number

    return nearest_keyframe



def extract_clip(video_path, start_time, clip_duration, output_file, keyframes):
    """
    Extracts a clip at the nearest keyframe to prevent audio delay.
    """
    nearest_keyframe = start_time
    # nearest_keyframe = get_nearest_keyframe(start_time, keyframes)
    # print(f"Adjusting start time: {start_time} → {nearest_keyframe}")

    # Ensure start time is even
    if nearest_keyframe % 2 != 0:
        nearest_keyframe -= 1  # Round down to nearest even number

    # Ensure the duration is also even
    if clip_duration % 2 != 0:
        clip_duration += 1  # Make duration an even number

    print(f"Adjusting start time: {nearest_keyframe} (forcing even timestamp)")

    ffmpeg_cmd = [
        "ffmpeg",
        "-i", video_path,
        "-ss", str(nearest_keyframe),  # Use nearest keyframe
        "-t", str(clip_duration),
        "-map", "0:v", "-map", "0:a:0",
        "-c:v", "copy",  # No video re-encoding
        "-c:a", "copy",  # No audio re-encoding unless necessary
        # "-c:a", "aac", "-b:a", "192k",  # Re-encode audio
        "-reset_timestamps", "1",
        "-avoid_negative_ts", "make_zero",
        "-y",
        output_file
    ]

    print(f"Extracting clip: {output_file} (Keyframe at {nearest_keyframe})")
    subprocess.run(ffmpeg_cmd)

def extract_clips(video_path, video_name, merged_intervals, keyframes):
    # Process each merged clip with FFmpeg
    clip_files = []
    for index, (start_time, end_time, description) in enumerate(merged_intervals):
        clip_duration = end_time - start_time
        output_file = os.path.join(output_folder, f"{video_name}_{index+1}_{description.replace(' ', '_')}.mp4")
        clip_files.append(output_file)
        extract_clip(video_path, start_time, clip_duration, output_file, keyframes)

    print(f"Clips extracted successfully for {video_name}!")
    return clip_files

def merge_overlapping_timestamps(timestamps):
    """
    Merges overlapping or closely spaced timestamps into single segments.
    - Start time is OVERLAPPING_BUFFER_START before the first timestamp.
    - End time is OVERLAPPING_BUFFER_END after the last overlapping timestamp.
    - Ensures no redundant clips are created due to minor gaps.
    """
    if not timestamps:
        return []

    # Sort timestamps to ensure sequential merging
    timestamps.sort()

    merged_intervals = []
    current_start = max(0, timestamps[0][0] - OVERLAPPING_BUFFER_START)
    current_end = timestamps[0][0] + OVERLAPPING_BUFFER_END
    current_descriptions = {timestamps[0][1]}  # Store unique descriptions

    for i in range(1, len(timestamps)):
        ts, desc = timestamps[i]
        adjusted_start = max(0, ts - OVERLAPPING_BUFFER_START)  # Actual start time for this timestamp

        # If adjusted start overlaps or falls within the current merged range
        if adjusted_start <= current_end: # Extend end time if needed
            current_end = max(current_end, ts + OVERLAPPING_BUFFER_END)  # Extend end time if needed
            current_descriptions.add(desc)  # Add unique descriptions
        else:
            # Store previous interval
            merged_intervals.append((current_start, current_end, "_".join(sorted(current_descriptions))))

            # Start new segment
            current_start = max(0, ts - OVERLAPPING_BUFFER_START)
            current_end = ts + OVERLAPPING_BUFFER_END
            current_descriptions = {desc}  # Reset description storage

    # Add last segment
    merged_intervals.append((current_start, current_end, "_".join(sorted(current_descriptions))))
    
    return merged_intervals

def merge_clips(clip_files):
    # ------------------ Merging Process ------------------
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

def process_videos():
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
        # keyframes = get_keyframes(video_path)
        keyframes = []

        timestamps = extract_timestamps(chapter_file)
        merged_intervals = merge_overlapping_timestamps(timestamps)
        clip_files = extract_clips(video_path, video_name, merged_intervals, keyframes)
        merge_clips(clip_files)
    print("All videos processed successfully!")

process_videos()