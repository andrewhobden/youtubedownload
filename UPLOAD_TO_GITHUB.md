# Instructions to Upload This Project to GitHub

## Quick Setup (Using GitHub CLI)

```bash
cd /Users/anhobden/Documents/GitHub/youtubedownload

# Initialize git repository
git init

# Add project files
git add .gitignore README.md requirements.txt download.py

# Create initial commit
git commit -m "Initial commit: YouTube downloader CLI tool

- Simple CLI interface for downloading YouTube videos
- Support for MP3 (audio) and MP4 (video) formats
- Comprehensive error handling
- Filename sanitization
- Progress feedback

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"

# Create GitHub repository and push
gh repo create youtubedownload --public --source=. --remote=origin \
  --description="Simple CLI tool to download YouTube videos as MP3 or MP4" \
  --push
```

## Alternative: Manual Setup

1. Create a new repository on GitHub: https://github.com/new
   - Repository name: `youtubedownload`
   - Description: "Simple CLI tool to download YouTube videos as MP3 or MP4"
   - Public repository
   - Don't initialize with README (we have one)

2. Run these commands:

```bash
cd /Users/anhobden/Documents/GitHub/youtubedownload

git init
git add .gitignore README.md requirements.txt download.py
git commit -m "Initial commit: YouTube downloader CLI tool"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/youtubedownload.git
git push -u origin main
```

Replace `YOUR_USERNAME` with your GitHub username.

## Project Files Ready for Commit

- ✓ `download.py` - Main CLI tool (310 lines)
- ✓ `requirements.txt` - Python dependencies
- ✓ `README.md` - Documentation
- ✓ `.gitignore` - Excludes downloaded MP3/MP4 files

The `.gitignore` file is configured to exclude all downloaded media files (*.mp3, *.mp4, etc.) so they won't be committed to the repository.
