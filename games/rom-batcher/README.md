# Rom Batcher
## Setup

### Linux
- For `debian` and `ubuntu` based OS

```shell
apt install git wget curl mame-tools ciso gzip bzip2 unzip p7zip-full rar
```

- You can install via homebrew, get it from [here](https://brew.sh/), once installed run

```shell
brew install wget curl rom-tools gzip bzip2 unzip p7zip rar
```

### MacOS
You would need homebrew, install it from [here](https://brew.sh/)
Once installed run the following
```shell
brew install wget curl rom-tools gzip bzip2 unzip p7zip rar
```

### Android (Termux Setup)
- Install Termux from [here](https://termux.com/)
- run the following
```shell
termux-setup-storage # Accept the Storage/Files Permission from the prompt
pkg update && pkg upgrade
pkg install -y x11-repo
pkg install -y git wget build-essential lld sdl2 binutils bunzip2 p7zip
wget https://github.com/Pipetto-crypto/mame/archive/refs/heads/termux-chdman.zip
unzip termux-chdman.zip
cd mame-termux-chdman
bash build-chdman.sh
```

Thanks to [u/uKnowIsOver](https://www.reddit.com/user/uKnowIsOver/) for the inspiration and this setup is based on their script from the [post](https://www.reddit.com/r/EmulationOnAndroid/comments/riqu81/guidedefinitiveconvert_your_games_with_chdman_on/) on [r/EmulationOnAndroid](https://www.reddit.com/r/EmulationOnAndroid) subreddit

## Script

Before running the script please go to the directory where you have stored your roms, for example

```shell
cd /path/to/roms
```

The script is interactive, to get started please run this command and follow the on screen instructions

```shell
bash <(curl -s https://raw.githubusercontent.com/FirzenYogesh/scripts/main/games/rom-batcher/rom-batcher.sh)
```

### Extraction
The script can extract till 3 sub directories deep
For example:
- `./game.zip` 
- `./console/game.zip` 
- `./manufacturer/console/game.zip`

### ISO to CHD
The script assumes that the roms are placed on folders based on either the console name or the emulator name

## Disclaimer

Please make sure you have backups of your roms before executing the script.

Please use this script on a test folder first, before using it on the main library.

I have tested this script on Android (Termux) and MacOS, it should work on Linux distros too.

I have not tested this on Windows, it could probably work on WSL2 (Windows Subsystem for Linux).
