#!/bin/bash
set -e

PKG="com.sec.app"
SDIR="app/src/main/java/com/sec/app"
RDIR="app/src/main/res"

# cria diretórios
mkdir -p $SDIR
mkdir -p $RDIR/values
mkdir -p app/src/main
mkdir -p gradle/wrapper
mkdir -p .github/workflows

# arquivos java
touch $SDIR/MainActivity.java
touch $SDIR/TelegramService.java
touch $SDIR/TgApi.java
touch $SDIR/CmdHandler.java
touch $SDIR/ModMedia.java
touch $SDIR/ModShot.java
touch $SDIR/ShotService.java
touch $SDIR/ShotActivity.java
touch $SDIR/BootReceiver.java

# resources e manifest
touch $RDIR/values/strings.xml
touch app/src/main/AndroidManifest.xml

# gradle e config
touch build.gradle
touch settings.gradle
touch gradle.properties
touch app/build.gradle
touch proguard-rules.pro

# github actions
touch .github/workflows/build.yml

echo "✅ estrutura criada:"
find . -type f -not -path "./.git/*" | sort
