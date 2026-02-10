#!/bin/bash

# Ensure we're in the right directory
cd "$(dirname "$0")"

dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- build --config Developer
dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- build-shaders
dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- build-content
