#!/bin/bash

set -e

echo "🚀 Starting release process..."

# Check if we're on main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "❌ Must be on main branch to release"
  exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Working directory must be clean"
  exit 1
fi

# Get current version
CURRENT_VERSION=$(node -p "require('./package.json').version")
echo "📦 Current version: $CURRENT_VERSION"

# Prompt for new version
echo "🔢 Enter new version (or press enter for patch):"
read NEW_VERSION

if [ -z "$NEW_VERSION" ]; then
  NEW_VERSION=$(npm version patch --no-git-tag-version | sed 's/v//')
else
  npm version $NEW_VERSION --no-git-tag-version
  NEW_VERSION=$(node -p "require('./package.json').version")
fi

echo "📝 New version: $NEW_VERSION"

# Run tests and build
echo "🧪 Running tests..."
npm test

echo "🔨 Building library..."
npm run build

echo "🔍 Linting code..."
npm run lint

echo "✅ All checks passed!"

# Commit changes
git add package.json
git commit -m "chore: release v$NEW_VERSION"

# Create tag
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

echo "🏷️  Created tag v$NEW_VERSION"

# Push changes and tags
echo "📤 Pushing changes..."
git push origin main
git push origin "v$NEW_VERSION"

echo "🎉 Release v$NEW_VERSION completed!"
echo "🚀 GitHub Actions will automatically publish to NPM"
