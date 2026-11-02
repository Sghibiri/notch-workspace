# Notch Workspace

Modified 2 November 2026. This is an independent local derivative of Boring Notch, not an official Boring Notch or DynamicLake release.

The upstream Boring Notch source is included in this repository at commit b7611bbf32c627a3427408fc142486900d71a23f (https://github.com/TheBoredTeam/boring.notch). Original copyright notices and the GPL-3.0 license are retained. The new Workspace target uses Boring Notch's NotchShape unchanged and adapts the music integration architecture of its NowPlayingController. The original Xcode application remains in its original directories.

NotchShape was originally created by Kai Azim for DynamicNotchKit and modified by Alexander for Boring Notch; see its source header. DynamicNotchKit's MIT license is included in Workspace/Resources and in the built app alongside the GPL-3.0 license governing this derivative.

MediaRemoteAdapter and mediaremote-adapter.pl are by Jonas van den Berg, used under BSD-3-Clause. Their license is included with this target and with the built app. Source: https://github.com/ungive/mediaremote-adapter . The bundled framework is retained from the upstream Boring Notch repository, including its existing signature.

All new Workspace source and this derivative as a whole are provided under GPL-3.0. There is no warranty. The complete corresponding source and build script accompany this app in the NotchWorkspace folder. DynamicLake's proprietary code, name, branding, and media are not included in the application.

Weather data is provided by Open-Meteo (https://open-meteo.com/) under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), with city data based on GeoNames (https://www.geonames.org/). The public endpoints are for non-commercial use under the provider terms (https://open-meteo.com/en/terms). Data is reformatted for display, rounded, and optionally converted to Fahrenheit. No provider library code is bundled.
