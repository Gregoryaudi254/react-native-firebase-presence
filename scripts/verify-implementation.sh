#!/bin/bash

echo "🔍 Verifying library implementation..."

# Check if all required files exist
FILES=(
    "src/PresenceService.ts"
    "src/types/index.ts"
    "src/utils/firebase.ts"
    "src/context/PresenceContext.tsx"
    "src/hooks/usePresence.ts"
    "src/hooks/useConnectionStatus.ts"
    "src/hooks/useUserPresence.ts"
    "src/hooks/useMultipleUsersPresence.ts"
    "src/hooks/usePresenceDebug.ts"
    "src/components/PresenceIndicator.tsx"
    "src/components/PresenceDebugPanel.tsx"
    "src/components/index.ts"
    "src/config/index.ts"
    "src/index.ts"
)

echo "📁 Checking required files..."
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file (missing)"
    fi
done

echo ""
echo "🔨 Testing TypeScript compilation..."
if npx tsc --noEmit; then
    echo "✅ TypeScript compilation successful"
else
    echo "❌ TypeScript compilation failed"
fi

echo ""
echo "🧪 Running tests..."
if npm test; then
    echo "✅ All tests passed"
else
    echo "❌ Some tests failed"
fi

echo ""
echo "🔍 Running linter..."
if npm run lint; then
    echo "✅ Linting passed"
else
    echo "❌ Linting issues found"
fi

echo ""
echo "📦 Building library..."
if npm run build; then
    echo "✅ Build successful"
    echo "📋 Generated files:"
    ls -la lib/ 2>/dev/null || echo "No lib directory found"
else
    echo "❌ Build failed"
fi

echo ""
echo "🎯 Verification complete!"
