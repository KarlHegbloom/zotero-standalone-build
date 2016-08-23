#!/bin/bash -e

# Copyright (c) 2011  Zotero
#                     Center for History and New Media
#                     George Mason University, Fairfax, Virginia, USA
#                     http://zotero.org
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

CALLDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CALLDIR/config.sh"

if [ "`uname`" = "Darwin" ]; then
	MAC_NATIVE=1
else
	MAC_NATIVE=0
fi
if [ "`uname -o 2> /dev/null`" = "Cygwin" ]; then
	WIN_NATIVE=1
else
	WIN_NATIVE=0
fi

function usage {
	cat >&2 <<DONE
Usage: $0 -f FILE -p PLATFORMS [-c CHANNEL] [-d]
Options
 -f FILE             ZIP file to build from
 -p PLATFORMS        build for platforms PLATFORMS (m=Mac, w=Windows, l=Linux)
 -c CHANNEL          use update channel CHANNEL
 -d                  don't package; only build binaries in staging/ directory
DONE
	exit 1
}

BUILD_DIR=`mktemp -d`
function cleanup {
	rm -rf $BUILD_DIR
}
trap cleanup EXIT

function abspath {
	echo $(cd $(dirname $1); pwd)/$(basename $1);
}

BUILD_MAC=0
BUILD_WIN32=0
BUILD_LINUX=0
PACKAGE=1
while getopts "f:p:c:d" opt; do
	case $opt in
		f)
			ZIP_FILE="$OPTARG"
			;;
		p)
			for i in `seq 0 1 $((${#OPTARG}-1))`
			do
				case ${OPTARG:i:1} in
					m) BUILD_MAC=1;;
					w) BUILD_WIN32=1;;
					l) BUILD_LINUX=1;;
					*)
						echo "$0: Invalid platform option ${OPTARG:i:1}"
						usage
						;;
				esac
			done
			;;
		c)
			UPDATE_CHANNEL="$OPTARG"
			;;
		d)
			PACKAGE=0
			;;
		*)
			usage
			;;
	esac
	shift $((OPTIND-1)); OPTIND=1
done

if [ -z "$ZIP_FILE" ]; then
	usage
fi

# Require at least one platform
if [[ $BUILD_MAC == 0 ]] && [[ $BUILD_WIN32 == 0 ]] && [[ $BUILD_LINUX == 0 ]]; then
	usage
fi

BUILD_ID=`date +%Y%m%d%H%M%S`

shopt -s extglob
mkdir -p "$BUILD_DIR/zotero"
rm -rf "$STAGE_DIR"
mkdir "$STAGE_DIR"
rm -rf "$DIST_DIR"
mkdir "$DIST_DIR"

# Save build id, which is needed for updates manifest
echo $BUILD_ID > $DIST_DIR/build_id

if [ -z "$UPDATE_CHANNEL" ]; then UPDATE_CHANNEL="default"; fi

ZIP_FILE="`abspath $ZIP_FILE`"
echo "Building from $ZIP_FILE"
unzip -q $ZIP_FILE -d "$BUILD_DIR/zotero"

cd "$BUILD_DIR/zotero"

VERSION=`perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' install.rdf`
if [ -z "$VERSION" ]; then
	echo "Version number not found in install.rdf"
	exit 1
fi
rm install.rdf

echo
echo "Version: $VERSION"

# Delete Mozilla signing info if present
rm -rf META-INF

# Copy branding
cp -R "$CALLDIR/assets/branding" "$BUILD_DIR/zotero/chrome/branding"

# Add to chrome manifest
echo "" >> "$BUILD_DIR/zotero/chrome.manifest"
cat "$CALLDIR/assets/chrome.manifest" >> "$BUILD_DIR/zotero/chrome.manifest"

# Delete files that shouldn't be distributed
find "$BUILD_DIR/zotero/chrome" -name .DS_Store -exec rm -f {} \;

# Zip chrome into JAR
cd "$BUILD_DIR/zotero"
zip -r -q zotero.jar chrome deleted.txt resource styles.zip translators.index translators.zip styles translators.json translators
rm -rf "chrome/"* install.rdf deleted.txt resource styles.zip translators.index translators.zip styles translators.json translators

# Copy updater.ini
cp "$CALLDIR/assets/updater.ini" "$BUILD_DIR/zotero"

# Adjust chrome.manifest
perl -pi -e 's^(chrome|resource)/^jar:zotero.jar\!/$1/^g' "$BUILD_DIR/zotero/chrome.manifest"

# Adjust connector pref
perl -pi -e 's/pref\("extensions\.zotero\.httpServer\.enabled", false\);/pref("extensions.zotero.httpServer.enabled", true);/g' "$BUILD_DIR/zotero/defaults/preferences/zotero.js"
perl -pi -e 's/pref\("extensions\.zotero\.connector\.enabled", false\);/pref("extensions.zotero.connector.enabled", true);/g' "$BUILD_DIR/zotero/defaults/preferences/zotero.js"

# Copy icons
cp -r "$CALLDIR/assets/icons" "$BUILD_DIR/zotero/chrome/icons"

# Copy application.ini and modify
cp "$CALLDIR/assets/application.ini" "$BUILD_DIR/application.ini"
perl -pi -e "s/\{\{VERSION}}/$VERSION/" "$BUILD_DIR/application.ini"
perl -pi -e "s/\{\{BUILDID}}/$BUILD_ID/" "$BUILD_DIR/application.ini"

# Copy prefs.js and modify
cp "$CALLDIR/assets/prefs.js" "$BUILD_DIR/zotero/defaults/preferences"
perl -pi -e 's/pref\("app\.update\.channel", "[^"]*"\);/pref\("app\.update\.channel", "'"$UPDATE_CHANNEL"'");/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION"'/g' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"

echo -n "Channel: "
grep app.update.channel "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
echo

# Remove unnecessary files
find "$BUILD_DIR" -name .DS_Store -exec rm -f {} \;
rm -rf "$BUILD_DIR/zotero/test"

cd "$CALLDIR"

# Mac
if [ $BUILD_MAC == 1 ]; then
	echo 'Building Zotero.app'
		
	# Set up directory structure
	APPDIR="$STAGE_DIR/Zotero.app"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	chmod 755 "$APPDIR"
	cp -r "$CALLDIR/mac/Contents" "$APPDIR"
	CONTENTSDIR="$APPDIR/Contents"
	
	# Modify platform-specific prefs
	perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
	
	# Merge relevant assets from Firefox
	mkdir "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/MacOS/"!(firefox-bin|crashreporter.app|updater.app) "$CONTENTSDIR/MacOS"
	cp -r "$MAC_RUNTIME_PATH/Contents/Resources/"!(application.ini|updater.ini|update-settings.ini|browser|precomplete|removed-files|webapprt*|*.icns|defaults|*.lproj) "$CONTENTSDIR/Resources"

	# Use our own launcher
	mv "$CONTENTSDIR/MacOS/firefox" "$CONTENTSDIR/MacOS/zotero-bin"
	cp "$CALLDIR/mac/zotero" "$CONTENTSDIR/MacOS/zotero"
	cp "$BUILD_DIR/application.ini" "$CONTENTSDIR/Resources"

	# Use our own updater, because Mozilla's requires updates signed by Mozilla
	cd "$CONTENTSDIR/MacOS"
	tar -xjf "$CALLDIR/mac/updater.tar.bz2"
	
	# Modify Info.plist
	perl -pi -e "s/{{VERSION}}/$VERSION/" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/{{VERSION_NUMERIC}}/$VERSION_NUMERIC/" "$CONTENTSDIR/Info.plist"
	# Needed for "monkeypatch" Windows builds: 
	# http://www.nntp.perl.org/group/perl.perl5.porters/2010/08/msg162834.html
	rm -f "$CONTENTSDIR/Info.plist.bak"
	
	# Add components
	cp -R "$BUILD_DIR/zotero/"* "$CONTENTSDIR/Resources"
	
	# Add Mac-specific Standalone assets
	cd "$CALLDIR/assets/mac"
	zip -r -q "$CONTENTSDIR/Resources/zotero.jar" *
	
	# Add word processor plug-ins
	mkdir "$CONTENTSDIR/Resources/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-mac-integration" "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroMacWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$CONTENTSDIR/Resources/extensions/$ext/install.rdf"
		rm -rf "$CONTENTSDIR/Resources/extensions/$ext/.git"
	done
	echo
	
	# Delete extraneous files
	find "$CONTENTSDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$CONTENTSDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
	find "$CONTENTSDIR/Resources/extensions" -depth -type d -name build -exec rm -rf {} \;

	# Copy over removed-files and make a precomplete file since it
	# needs to be stable for the signature
	cp "$CALLDIR/update-packaging/removed-files_mac" "$CONTENTSDIR/Resources/removed-files"
	touch "$CONTENTSDIR/Resources/precomplete"
	
	# Sign
	if [ $SIGN == 1 ]; then
		/usr/bin/codesign --force --sign "$DEVELOPER_ID" "$APPDIR/Contents/MacOS/updater.app/Contents/MacOS/updater"
		/usr/bin/codesign --force --sign "$DEVELOPER_ID" "$APPDIR/Contents/MacOS/updater.app"
		/usr/bin/codesign --force --sign "$DEVELOPER_ID" "$APPDIR/Contents/MacOS/zotero-bin"
		/usr/bin/codesign --force --sign "$DEVELOPER_ID" "$APPDIR"
		/usr/bin/codesign --verify -vvvv "$APPDIR"
	fi
	
	# Build disk image
	if [ $PACKAGE == 1 ]; then
		if [ $MAC_NATIVE == 1 ]; then
			echo 'Creating Mac installer'
			"$CALLDIR/mac/pkg-dmg" --source "$STAGE_DIR/Zotero.app" \
				--target "$DIST_DIR/Zotero-$VERSION.dmg" \
				--sourcefile --volname Zotero --copy "$CALLDIR/mac/DSStore:/.DS_Store" \
				--symlink /Applications:"/Drag Here to Install" > /dev/null
		else
			echo 'Not building on Mac; creating Mac distribution as a zip file'
			rm -f "$DIST_DIR/Zotero_mac.zip"
			cd "$STAGE_DIR" && zip -rqX "$DIST_DIR/Zotero-${VERSION}_mac.zip" Zotero.app
		fi
	fi
fi

# Win32
if [ $BUILD_WIN32 == 1 ]; then
	echo 'Building Zotero_win32'
	
	# Set up directory
	APPDIR="$STAGE_DIR/Zotero_win32"
	mkdir "$APPDIR"
	
	# Merge xulrunner and relevant assets
	cp -R "$BUILD_DIR/zotero/"* "$BUILD_DIR/application.ini" "$APPDIR"
	cp -r "$WIN32_RUNTIME_PATH" "$APPDIR/xulrunner"
	
	cat "$CALLDIR/win/installer/updater_append.ini" >> "$APPDIR/updater.ini"
	mv "$APPDIR/xulrunner/xulrunner-stub.exe" "$APPDIR/zotero.exe"
	
	# This used to be bug 722810, but that bug was actually fixed for Gecko 12.
	# Then it was broken again. Now it seems okay...
	# cp "$WIN32_RUNTIME_PATH/msvcp120.dll" \
	#    "$WIN32_RUNTIME_PATH/msvcr120.dll" \
	#    "$APPDIR/"
	
	# Add Windows-specific Standalone assets
	cd "$CALLDIR/assets/win"
	zip -r -q "$APPDIR/zotero.jar" *
	
	# Add word processor plug-ins
	mkdir "$APPDIR/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-windows-integration" "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
	echo
	for ext in "zoteroWinWordIntegration@zotero.org" "zoteroOpenOfficeIntegration@zotero.org"; do
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/$ext/install.rdf"
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/$ext/install.rdf"
		rm -rf "$APPDIR/extensions/$ext/.git"
	done
	echo

	# Delete extraneous files
	rm "$APPDIR/xulrunner/js.exe" "$APPDIR/xulrunner/redit.exe"
	find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$APPDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
	find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
	find "$APPDIR" \( -name '*.exe' -or -name '*.dll' \) -exec chmod 755 {} \;
	
	if [ $PACKAGE == 1 ]; then
		if [ $WIN_NATIVE == 1 ]; then
			INSTALLER_PATH="$DIST_DIR/Zotero-${VERSION}_setup.exe"
			
			# Add icon to xulrunner-stub
			"$CALLDIR/win/ReplaceVistaIcon/ReplaceVistaIcon.exe" "`cygpath -w \"$APPDIR/zotero.exe\"`" \
				"`cygpath -w \"$CALLDIR/assets/icons/default/main-window.ico\"`"
			
			echo 'Creating Windows installer'
			# Copy installer files
			cp -r "$CALLDIR/win/installer" "$BUILD_DIR/win_installer"
			
			# Build and sign uninstaller
			perl -pi -e "s/{{VERSION}}/$VERSION/" "$BUILD_DIR/win_installer/defines.nsi"
			"`cygpath -u \"$MAKENSISU\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/uninstaller.nsi\"`"
			mkdir "$APPDIR/uninstall"
			mv "$BUILD_DIR/win_installer/helper.exe" "$APPDIR/uninstall"
			
			# Sign zotero.exe, dlls, updater, and uninstaller
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$APPDIR/zotero.exe\"`"
				for dll in "$APPDIR/"*.dll "$APPDIR/xulrunner/"*.dll; do
					"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero" \
						/du "$SIGNATURE_URL" "`cygpath -w \"$dll\"`"
				done
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Updater" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$APPDIR/xulrunner/updater.exe\"`"
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Uninstaller" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$APPDIR/uninstall/helper.exe\"`"
			fi
			
			# Stage installer
			INSTALLER_STAGE_DIR="$BUILD_DIR/win_installer/staging"
			mkdir "$INSTALLER_STAGE_DIR"
			cp -R "$APPDIR" "$INSTALLER_STAGE_DIR/core"
			
			# Build and sign setup.exe
			"`cygpath -u \"$MAKENSISU\"`" /V1 "`cygpath -w \"$BUILD_DIR/win_installer/installer.nsi\"`"
			mv "$BUILD_DIR/win_installer/setup.exe" "$INSTALLER_STAGE_DIR"
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Setup" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$INSTALLER_STAGE_DIR/setup.exe\"`"
			fi
			
			# Compress application
			cd "$INSTALLER_STAGE_DIR" && "`cygpath -u \"$EXE7ZIP\"`" a -r -t7z "`cygpath -w \"$BUILD_DIR/app_win32.7z\"`" \
				-mx -m0=BCJ2 -m1=LZMA:d24 -m2=LZMA:d19 -m3=LZMA:d19  -mb0:1 -mb0s1:2 -mb0s2:3 > /dev/null
				
			# Compress 7zSD.sfx
			"`cygpath -u \"$UPX\"`" --best -o "`cygpath -w \"$BUILD_DIR/7zSD.sfx\"`" \
				"`cygpath -w \"$CALLDIR/win/installer/7zstub/firefox/7zSD.sfx\"`" > /dev/null
			
			# Combine 7zSD.sfx and app.tag into setup.exe
			cat "$BUILD_DIR/7zSD.sfx" "$CALLDIR/win/installer/app.tag" \
				"$BUILD_DIR/app_win32.7z" > "$INSTALLER_PATH"
			
			# Sign Zotero_setup.exe
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Setup" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$INSTALLER_PATH\"`"
			fi
			
			chmod 755 "$INSTALLER_PATH"
		else
			echo 'Not building on Windows; only building zip file'
		fi
		cd "$STAGE_DIR" && zip -rqX "$DIST_DIR/Zotero-${VERSION}_win32.zip" Zotero_win32
	fi
fi

# Linux
if [ $BUILD_LINUX == 1 ]; then
	for arch in "i686" "x86_64"; do
		RUNTIME_PATH=`eval echo '$LINUX_'$arch'_RUNTIME_PATH'`
		
		# Set up directory
		echo 'Building Zotero_linux-'$arch
		APPDIR="$STAGE_DIR/Zotero_linux-$arch"
		rm -rf "$APPDIR"
		mkdir "$APPDIR"
		
		# Merge relevant assets from Firefox
		cp -r "$RUNTIME_PATH/"!(application.ini|browser|defaults|crashreporter|crashreporter.ini|firefox-bin|precomplete|removed-files|run-mozilla.sh|update-settings.ini|updater|updater.ini) "$APPDIR"
		
		# Use our own launcher that calls the original Firefox executable with -app
		mv "$APPDIR"/firefox "$APPDIR"/zotero-bin
		cp "$CALLDIR/linux/zotero" "$APPDIR"/zotero
		
		# Use our own updater, because Mozilla's requires updates signed by Mozilla
		cp "$CALLDIR/linux/updater-$arch" "$APPDIR"/updater
		
		cp -R "$BUILD_DIR/zotero/"* "$BUILD_DIR/application.ini" "$APPDIR"
		
		# Modify platform-specific prefs
		perl -pi -e 's/pref\("browser\.preferences\.instantApply", false\);/pref\("browser\.preferences\.instantApply", true);/' "$BUILD_DIR/zotero/defaults/preferences/prefs.js"
		
		# Add Unix-specific Standalone assets
		cd "$CALLDIR/assets/unix"
		zip -0 -r -q "$APPDIR/zotero.jar" *
		
		# Add word processor plug-ins
		mkdir "$APPDIR/extensions"
		cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
		perl -pi -e 's/\.SOURCE<\/em:version>/.SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		echo -n "$ext Version: "
		perl -ne 'print and last if s/.*<em:version>(.*)<\/em:version>.*/\1/;' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		echo
		rm -rf "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/.git"
		
		# Delete extraneous files
		find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
		find "$APPDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
		find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
		
		# Add run-zotero.sh
		#cp "$CALLDIR/linux/run-zotero.sh" "$APPDIR/run-zotero.sh"
		
		if [ $PACKAGE == 1 ]; then
			# Create tar
			rm -f "$DIST_DIR/Zotero-${VERSION}_linux-$arch.tar.bz2"
			cd "$STAGE_DIR"
			tar -cjf "$DIST_DIR/Zotero-${VERSION}_linux-$arch.tar.bz2" "Zotero_linux-$arch"
		fi
	done
fi

rm -rf $BUILD_DIR
