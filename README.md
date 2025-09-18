# react-native-firebase-presence

A comprehensive React Native library for Firebase real-time presence management with hooks, providers, and components.

[![npm version](https://badge.fury.io/js/react-native-firebase-presence.svg)](https://badge.fury.io/js/react-native-firebase-presence)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TypeScript](https://img.shields.io/badge/%3C%2F%3E-TypeScript-%230074c1.svg)](http://www.typescriptlang.org/)

## 🚀 Features

- ✅ Real-time presence synchronization
- 🎣 Modern React hooks API  
- 🔄 Automatic retry logic with exponential backoff
- 📱 App state awareness (foreground/background)
- 🎨 Ready-to-use UI components
- 📊 Debug tools and comprehensive logging
- 🔧 TypeScript support
- ⚡ Performance optimized
- 🛡️ Robust error handling

## 📦 Installation

```bash
npm install react-native-firebase-presence
# or
yarn add react-native-firebase-presence
```

## 🚀 Quick Start

```typescript
import React from 'react';
import { PresenceProvider, usePresence } from 'react-native-firebase-presence';
import { app, auth, database } from './firebase.config';

const presenceConfig = {
  firebaseApp: app,
  database,
  auth,
  debug: __DEV__
};

function MyApp() {
  return (
    <PresenceProvider config={presenceConfig}>
      <MyComponent />
    </PresenceProvider>
  );
}

function MyComponent() {
  const { currentState, setOnline, setAway } = usePresence();
  
  return (
    <View>
      <Text>Status: {currentState}</Text>
      <Button title="Go Online" onPress={() => setOnline()} />
      <Button title="Set Away" onPress={() => setAway()} />
    </View>
  );
}
```

## 📖 Documentation

- [API Reference](./docs/api.md)
- [Examples](./docs/examples.md)
- [Contributing](./CONTRIBUTING.md)

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](./CONTRIBUTING.md) for details.

## 📄 License

MIT © [Gregoryaudi254](https://github.com/gregoryaudi254)
