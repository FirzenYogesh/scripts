# Rom Batcher
## Setup
To run this script you would need some prequisite softwares
- curl or wget
- chdman
- unzip

### Linux
Work in progress

### MacOS
You would need homebrew, install it from [here](https://brew.sh/)
Once installed run the following
```shell
$ brew install rom-tools
```

### Termux Setup
- Install Termux from [here](https://termux.com/)
- run the following
```shell
$ termux-setup-storage # Accept the Storage/Files Permission from the prompt
$ pkg update
$ pkg upgrade
$ pkg install -y wget
$ pkg install -y x11-repo
$ pkg install -y git build-essential lld sdl2 binutils
$ wget https://github.com/Pipetto-crypto/mame/archive/refs/heads/termux-chdman.zip
$ unzip termux-chdman.zip
$ cd mame-termux-chdman
$ bash build-chdman.sh
```

Thanks to [u/uKnowIsOver](https://www.reddit.com/user/uKnowIsOver/) for the inspiration and this setup is based on their script from the [post](https://www.reddit.com/r/EmulationOnAndroid/comments/riqu81/guidedefinitiveconvert_your_games_with_chdman_on/) on [r/EmulationOnAndroid](https://www.reddit.com/r/EmulationOnAndroid) subreddit

## Script

Before running the script please go to the directory where you have stored your roms, for example

```shell
$ cd /path/to/roms
```

The script is interactive, to get started please run this command and follow the on screen instructions

```shell
$ curl -o- https://raw.githubusercontent.com/FirzenYogesh/game-scripts/main/rom-batcher/rom-batcher.sh | bash
```

or

```shell
$ wget -qO- https://raw.githubusercontent.com/FirzenYogesh/game-scripts/main/rom-batcher/rom-batcher.sh | bash
```

## Extraction
The script can extract till 3 sub directories deep
For example:
- `./game.zip` 
- `./console/game.zip` 
- `./manufacturer/console/game.zip`

## ISO to CHD
The script assumes that the roms are placed on folders based on either the console name or the emulator name

## Disclaimer

I have tested this script on Android (Termux) and MacOS, it should work on Linux distros too. I have not tested this on Windows.



Please use this script on a test folder, before using it on the main library.