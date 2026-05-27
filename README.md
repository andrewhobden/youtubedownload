# YouTube Downloader CLI Tool

A simple command-line tool to download YouTube videos as MP4 (video) or MP3 (audio).

## Requirements

- Python 3.7 or higher
- ffmpeg (for audio conversion to MP3)

### Installing ffmpeg

**macOS** (using Homebrew):
```bash
brew install ffmpeg
```

**Ubuntu/Debian**:
```bash
sudo apt update
sudo apt install ffmpeg
```

**Windows**:
Download from [ffmpeg.org](https://ffmpeg.org/download.html) and add to PATH.

## Installation

1. Clone this repository
2. Install Python dependencies:
```bash
pip install -r requirements.txt
```

## Usage

```bash
python download.py <youtube_url> <format>
```

**Parameters:**
- `<youtube_url>`: The full YouTube video URL
- `<format>`: Either `mp3` (audio only) or `mp4` (video with audio)

**Examples:**

Download video as MP4:
```bash
python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp4
```

Download audio as MP3:
```bash
python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp3
```

## Output

Downloaded files are saved to the current directory with the video title as the filename.

## Notes

- Requires active internet connection
- Respects YouTube's terms of service - only download content you have rights to
- MP3 conversion requires ffmpeg to be installed on your system
