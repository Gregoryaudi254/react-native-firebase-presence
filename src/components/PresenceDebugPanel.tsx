import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Modal,
  SafeAreaView
} from 'react-native';
import { usePresenceDebug } from '../hooks/usePresenceDebug';
import { useConnectionStatus } from '../hooks/useConnectionStatus';
import { usePresence } from '../hooks/usePresence';

interface PresenceDebugPanelProps {
  visible: boolean;
  onClose: () => void;
}

export const PresenceDebugPanel: React.FC<PresenceDebugPanelProps> = ({
  visible,
  onClose
}) => {
  const debugInfo = usePresenceDebug();
  const { connectionStatus } = useConnectionStatus();
  const { currentState, setOnline, setOffline, setAway, setBusy } = usePresence();
  const [refreshKey, setRefreshKey] = useState(0);

  const handleStateChange = async (state: string) => {
    try {
      switch (state) {
        case 'online':
          await setOnline();
          break;
        case 'offline':
          await setOffline();
          break;
        case 'away':
          await setAway();
          break;
        case 'busy':
          await setBusy();
          break;
      }
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      console.error('Error changing state:', error);
    }
  };

  const renderDebugItem = (label: string, value: any) => (
    <View style={styles.debugItem}>
      <Text style={styles.debugLabel}>{label}:</Text>
      <Text style={styles.debugValue}>
        {typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value)}
      </Text>
    </View>
  );

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>Presence Debug Panel</Text>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>Close</Text>
          </TouchableOpacity>
        </View>

        <ScrollView style={styles.content}>
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Current State Controls</Text>
            <View style={styles.buttonRow}>
              {['online', 'offline', 'away', 'busy'].map(state => (
                <TouchableOpacity
                  key={state}
                  style={[
                    styles.stateButton,
                    currentState === state && styles.activeStateButton
                  ]}
                  onPress={() => handleStateChange(state)}
                >
                  <Text
                    style={[
                      styles.stateButtonText,
                      currentState === state && styles.activeStateButtonText
                    ]}
                  >
                    {state.charAt(0).toUpperCase() + state.slice(1)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Connection Status</Text>
            {renderDebugItem('Is Connected', connectionStatus.isConnected)}
            {renderDebugItem('Last Connected', connectionStatus.lastConnected?.toLocaleString() || 'Never')}
            {renderDebugItem('Retry Count', connectionStatus.retryCount)}
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Service State</Text>
            {renderDebugItem('Initialized', debugInfo.initialized)}
            {renderDebugItem('Current User', debugInfo.currentUser || 'None')}
            {renderDebugItem('Setup In Progress', debugInfo.setupInProgress)}
            {renderDebugItem('Current Setup UID', debugInfo.currentSetupUid || 'None')}
            {renderDebugItem('Current Presence State', debugInfo.currentPresenceState)}
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>References</Text>
            {renderDebugItem('User Ref', debugInfo.userRef)}
            {renderDebugItem('Connected Ref', debugInfo.connectedRef)}
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Listeners</Text>
            {renderDebugItem('Connection Listeners', debugInfo.listenersCount)}
            {renderDebugItem('Presence Listeners', debugInfo.presenceListenersCount)}
          </View>
        </ScrollView>
      </SafeAreaView>
    </Modal>
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
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0'
  },
  title: {
    fontSize: 18,
    fontWeight: 'bold'
  },
  closeButton: {
    padding: 8
  },
  closeButtonText: {
    color: '#007AFF',
    fontSize: 16
  },
  content: {
    flex: 1,
    padding: 16
  },
  section: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 12,
    color: '#333'
  },
  debugItem: {
    marginBottom: 8
  },
  debugLabel: {
    fontSize: 14,
    fontWeight: '500',
    color: '#666',
    marginBottom: 2
  },
  debugValue: {
    fontSize: 14,
    color: '#333',
    fontFamily: 'monospace'
  },
  buttonRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8
  },
  stateButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 16,
    backgroundColor: '#e0e0e0',
    minWidth: 70,
    alignItems: 'center'
  },
  activeStateButton: {
    backgroundColor: '#007AFF'
  },
  stateButtonText: {
    fontSize: 14,
    fontWeight: '500',
    color: '#333'
  },
  activeStateButtonText: {
    color: '#fff'
  }
});
