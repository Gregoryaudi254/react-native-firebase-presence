import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView
} from 'react-native';
import {
  PresenceProvider,
  usePresence,
  useConnectionStatus,
  useUserPresence,
  PresenceIndicator,
  PresenceDebugPanel
} from 'react-native-firebase-presence';

// You need to configure your Firebase here
const presenceConfig = {
  firebaseApp: {}, // Your Firebase app instance
  database: {}, // Your Firebase database instance
  auth: {}, // Your Firebase auth instance
  debug: __DEV__
};

const AppContent: React.FC = () => {
  const [showDebug, setShowDebug] = useState(false);
  const { currentState, setOnline, setOffline, setAway, setBusy } = usePresence();
  const { isConnected } = useConnectionStatus();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Presence Demo</Text>
        <TouchableOpacity 
          onPress={() => setShowDebug(true)}
          style={styles.debugButton}
        >
          <Text style={styles.debugButtonText}>Debug</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Connection Status</Text>
        <Text style={styles.statusText}>
          {isConnected ? '🟢 Connected' : '🔴 Disconnected'}
        </Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Current State: {currentState}</Text>
        <View style={styles.buttonGrid}>
          {[
            { state: 'online', handler: setOnline },
            { state: 'offline', handler: setOffline },
            { state: 'away', handler: setAway },
            { state: 'busy', handler: setBusy }
          ].map(({ state, handler }) => (
            <TouchableOpacity
              key={state}
              style={[
                styles.stateButton,
                currentState === state && styles.activeButton
              ]}
              onPress={() => handler()}
            >
              <Text style={styles.stateButtonText}>
                {state.charAt(0).toUpperCase() + state.slice(1)}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      <PresenceDebugPanel 
        visible={showDebug}
        onClose={() => setShowDebug(false)}
      />
    </SafeAreaView>
  );
};

const App: React.FC = () => {
  return (
    <PresenceProvider config={presenceConfig}>
      <AppContent />
    </PresenceProvider>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5'
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#fff'
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold'
  },
  debugButton: {
    padding: 8,
    backgroundColor: '#007AFF',
    borderRadius: 4
  },
  debugButtonText: {
    color: '#fff',
    fontSize: 14
  },
  section: {
    backgroundColor: '#fff',
    margin: 16,
    padding: 16,
    borderRadius: 8
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 12
  },
  statusText: {
    fontSize: 14,
    marginVertical: 4
  },
  buttonGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8
  },
  stateButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: '#e0e0e0',
    borderRadius: 16,
    minWidth: 80,
    alignItems: 'center'
  },
  activeButton: {
    backgroundColor: '#007AFF'
  },
  stateButtonText: {
    fontSize: 12,
    fontWeight: '500'
  }
});

export default App;
