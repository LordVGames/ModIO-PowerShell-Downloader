# Mod.IO PowerShell Downloader

This PowerShell script can download either a single URL or multiple, both to a location defined in it's settings file.

## Dependencies

The script is dependent on only 1 PowerShell module, that being [PSWriteColor](https://www.powershellgallery.com/packages/PSWriteColor). If it hasn't already been installed, the script will ask if it's OK to install it for you.

## How to use

Simply download the latest release's `.bat` and `.ps1` files. To run the script, run the `.bat` file.

Upon first run,  it will generate a `.conf` file. Open this up and enter your Mod.IO API key at the `ApiKey` setting. If you don't have one, go to the `Access` section of your profile settings to get one.

By default, the script will download to your `Downloads` folder on Windows, unknown where it will download to on Linux. Either way, you can change the location to your liking.
