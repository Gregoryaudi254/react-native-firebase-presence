#!/bin/bash

# implement-library.sh - Complete Library Implementation Script
# Run this AFTER the setup-repo.sh script in the project directory

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Implementing React Native Firebase Presence Library...${NC}"
echo ""

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    print_error "package.json not found. Make sure you're in the library root directory."
    echo "Expected structure:"
    echo "  react-native-firebase-presence/"
    echo "  ├── package.json"
    echo "  ├── src/"
    echo "  └── ..."
    exit 1
fi

# Check if this looks like our library
if ! grep -q "react-native-firebase-presence" package.json; then
    print_warning "This doesn't look like the Firebase Presence library directory. Continuing anyway..."
fi

echo -e "${BLUE}📝 Creating complete library implementation...${NC}"

# 1. Create complete types
echo -e "${YELLOW}Creating types...${NC}"
cat > src/types/index.ts << 'EOF'
export interface PresenceState {
  state: 'online' | 'offline' | 'away' | 'busy';
  lastChanged: any;
  customData?: Record<string, any>;
  uid?: string;
}

export interface PresenceConfig {
  firebaseApp?: any;
  database?: any;
  auth?: any;
  databasePath?: string;
  offlineTimeout?: number;
  retryInterval?: number;
  maxRetries?: number;
  debug?: boolean;
  customStates?: string[];
  autoSetAway?: boolean;
  awayTimeout?: number;
}

export interface ConnectionStatus {
  isConnected: boolean;
  lastConnected: Date | null;
  retryCount: number;
}

export class PresenceError extends Error {
  constructor(
    message: string,
    public code: string,
    public originalError?: Error
  ) {
    super(message);
    this.name = 'PresenceError';
  }
}
EOF
print_status "Types created"

# 2. Create Firebase utilities
echo -e "${YELLOW}Creating Firebase utilities...${NC}"
cat > src/utils/firebase.ts << 'EOF'
import { PresenceConfig, PresenceError } from '../types';

export class FirebaseValidator {
  static validateConfig(config: PresenceConfig): void {
    if (!config.firebaseApp) {
      throw new PresenceError(
        'Firebase app is required',
        'MISSING_FIREBASE_APP'
      );
    }
    
    if (!config.database) {
      throw new PresenceError(
        'Firebase database is required',
        'MISSING_DATABASE'
      );
    }
    
    if (!config.auth) {
      throw new PresenceError(
        'Firebase auth is required',
        'MISSING_AUTH'
      );
    }
  }

  static createRetryDelay(attempt: number, baseDelay: number = 1000): number {
    return Math.min(baseDelay * Math.pow(2, attempt), 30000);
  }
}
EOF
print_status "Firebase utilities created"

# 3. Create complete PresenceService
echo -e "${YELLOW}Creating PresenceService...${NC}"
cat > src/PresenceService.ts << 'EOF'
import { AppState, AppStateStatus } from 'react-native';
import { onAuthStateChanged, User } from 'firebase/auth';
import { onDisconnect, onValue, ref, serverTimestamp, set } from 'firebase/database';
import { PresenceState, PresenceConfig, ConnectionStatus, PresenceError } from './types';
import { FirebaseValidator } from './utils/firebase';

export class PresenceService {
  private config: Required<PresenceConfig>;
  private userRef: any = null;
  private connectedRef: any = null;
  private connectedListener: (() => void) | null = null;
  private connectionStatus: ConnectionStatus = {
    isConnected: false,
    lastConnected: null,
    retryCount: 0
  };
  private currentUser: User | null = null;
  private listeners: Set<(status: ConnectionStatus) => void> = new Set();
  private presenceListeners: Map<string, Set<(presence: PresenceState | null) => void>> = new Map();
  private authUnsubscribe: (() => void) | null = null;
  private appStateUnsubscribe: any = null;
  private initialized = false;
  private initPromise: Promise<void> | null = null;
  private setupInProgress = false;
  private currentSetupUid: string | null = null;
  private retryTimeout: NodeJS.Timeout | null = null;
  private awayTimeout: NodeJS.Timeout | null = null;
  private currentPresenceState: PresenceState['state'] = 'offline';

  constructor(config: PresenceConfig = {}) {
    this.config = {
      databasePath: 'presence',
      offlineTimeout: 30000,
      retryInterval: 1000,
      maxRetries: 5,
      debug: false,
      customStates: ['online', 'offline', 'away', 'busy'],
      autoSetAway: true,
      awayTimeout: 300000,
      ...config
    } as Required<PresenceConfig>;

    this.initialize();
  }

  private log(...args: any[]) {
    if (this.config.debug) {
      console.log('[PresenceService]', ...args);
    }
  }

  private logError(...args: any[]) {
    if (this.config.debug) {
      console.error('[PresenceService]', ...args);
    }
  }

  private async initialize() {
    if (this.initPromise) return this.initPromise;
    
    this.initPromise = this._initialize();
    return this.initPromise;
  }

  private async _initialize() {
    if (this.initialized) return;
    
    try {
      this.log('Initializing presence service...');
      
      FirebaseValidator.validateConfig(this.config);
      
      if (!this.config.auth || !this.config.database) {
        throw new PresenceError(
          'Firebase services not ready',
          'SERVICES_NOT_READY'
        );
      }

      this.initialized = true;
      this.log('Presence service initialized');
      
      this.authUnsubscribe = onAuthStateChanged(this.config.auth, (user) => {
        this.handleAuthStateChange(user);
      });

      this.setupAppStateListener();
      
    } catch (error) {
      this.logError('Error initializing presence service:', error);
      this.initialized = false;
      this.initPromise = null;
      throw error instanceof PresenceError ? error : new PresenceError(
        'Failed to initialize presence service',
        'INIT_FAILED',
        error as Error
      );
    }
  }

  private handleAuthStateChange(user: User | null) {
    this.log('Auth state changed:', {
      newUid: user?.uid,
      previousUid: this.currentUser?.uid,
      currentSetupUid: this.currentSetupUid
    });
    
    if (user && user.uid !== this.currentSetupUid) {
      this.currentUser = user;
      this.currentSetupUid = user.uid;
      this.setupPresence(user.uid);
    } else if (!user) {
      this.currentSetupUid = null;
      if (this.currentUser) {
        this.log('User signed out, cleaning up');
        this.cleanup();
        this.currentUser = null;
      }
    }
  }

  private setupAppStateListener() {
    this.appStateUnsubscribe = AppState.addEventListener('change', (nextAppState: AppStateStatus) => {
      this.log('App state changed:', nextAppState, 'Current user:', this.currentUser?.uid);
      
      if (this.currentUser && this.userRef) {
        this.handleAppStateChange(nextAppState);
      }
    });
  }

  private handleAppStateChange(appState: AppStateStatus) {
    if (this.awayTimeout) {
      clearTimeout(this.awayTimeout);
      this.awayTimeout = null;
    }

    switch (appState) {
      case 'active':
        this.log('App became active, setting online');
        this.setPresenceState('online');
        this.setupAwayTimer();
        break;
      case 'background':
      case 'inactive':
        this.log('App went to background, setting offline');
        this.setPresenceState('offline');
        break;
    }
  }

  private setupAwayTimer() {
    if (!this.config.autoSetAway) return;

    this.awayTimeout = setTimeout(() => {
      if (this.currentPresenceState === 'online') {
        this.log('Auto-setting user to away due to inactivity');
        this.setPresenceState('away');
      }
    }, this.config.awayTimeout);
  }

  private async setupPresence(uid: string) {
    if (this.setupInProgress) {
      this.log('Setup already in progress, skipping');
      return;
    }
    
    this.setupInProgress = true;
    
    try {
      this.log('Setting up presence for user:', uid);
      
      if (!this.config.database) {
        throw new PresenceError('Database not available', 'DATABASE_UNAVAILABLE');
      }
      
      this.cleanup();
      
      this.userRef = ref(this.config.database, `${this.config.databasePath}/${uid}`);
      this.connectedRef = ref(this.config.database, '.info/connected');

      this.log('UserRef created:', !!this.userRef);

      this.connectedListener = onValue(this.connectedRef, (snapshot) => {
        const connected = snapshot.val();
        this.handleConnectionChange(connected);
      }, (error) => {
        this.logError('Connection listener error:', error);
        this.handleConnectionError(error);
      });

      if (this.userRef) {
        this.log('Setting initial online status');
        await this.setPresenceState('online');
        this.setupAwayTimer();
      }
      
    } catch (error) {
      this.logError('Error setting up presence:', error);
      this.userRef = null;
      this.handleSetupError(error);
    } finally {
      this.setupInProgress = false;
    }
  }

  private handleConnectionChange(connected: boolean) {
    this.log('Connection status changed:', connected);
    
    const wasConnected = this.connectionStatus.isConnected;
    this.connectionStatus.isConnected = connected;
    
    if (connected) {
      this.connectionStatus.lastConnected = new Date();
      this.connectionStatus.retryCount = 0;
      
      if (!wasConnected && this.userRef) {
        this.setPresenceState(this.currentPresenceState || 'online');
      }
    }
    
    this.notifyConnectionListeners();
    
    if (!connected) {
      this.scheduleRetry();
    }
  }

  private handleConnectionError(error: any) {
    this.connectionStatus.retryCount++;
    this.logError('Connection error, retry count:', this.connectionStatus.retryCount, error);
    this.scheduleRetry();
  }

  private handleSetupError(error: any) {
    this.connectionStatus.retryCount++;
    if (this.connectionStatus.retryCount < this.config.maxRetries) {
      this.scheduleRetry();
    } else {
      this.logError('Max retries reached, giving up');
    }
  }

  private scheduleRetry() {
    if (this.retryTimeout || this.connectionStatus.retryCount >= this.config.maxRetries) {
      return;
    }

    const delay = FirebaseValidator.createRetryDelay(
      this.connectionStatus.retryCount,
      this.config.retryInterval
    );

    this.log(`Scheduling retry in ${delay}ms (attempt ${this.connectionStatus.retryCount + 1})`);

    this.retryTimeout = setTimeout(() => {
      this.retryTimeout = null;
      if (this.currentUser && !this.connectionStatus.isConnected) {
        this.setupPresence(this.currentUser.uid);
      }
    }, delay);
  }

  public async setPresenceState(
    state: PresenceState['state'],
    customData?: Record<string, any>
  ): Promise<void> {
    if (!this.userRef) {
      this.log('Cannot set presence state: userRef is null');
      return;
    }

    if (!this.currentUser) {
      this.log('Cannot set presence state: no current user');
      return;
    }

    if (!this.config.customStates.includes(state)) {
      throw new PresenceError(
        `Invalid presence state: ${state}`,
        'INVALID_STATE'
      );
    }

    this.log('Setting user presence state:', state);
    this.currentPresenceState = state;

    try {
      const presenceData: PresenceState = {
        state,
        lastChanged: serverTimestamp(),
        uid: this.currentUser.uid,
        ...(customData && { customData })
      };

      await set(this.userRef, presenceData);
      this.log('Successfully set presence state:', state);

      if (state === 'online') {
        await onDisconnect(this.userRef).set({
          state: 'offline' as const,
          lastChanged: serverTimestamp(),
          uid: this.currentUser.uid,
          ...(customData && { customData })
        });
        this.log('OnDisconnect handler set');
      }
      
    } catch (error) {
      this.logError('Error setting presence state:', error);
      throw new PresenceError(
        'Failed to set presence state',
        'SET_STATE_FAILED',
        error as Error
      );
    }
  }

  private cleanup() {
    try {
      this.log('Cleaning up presence service');
      
      if (this.connectedListener) {
        this.log('Removing connection listener');
        this.connectedListener();
        this.connectedListener = null;
      }

      if (this.userRef) {
        this.log('Cleaning up userRef and onDisconnect');
        try {
          onDisconnect(this.userRef).cancel();
        } catch (error) {
          this.logError('Error canceling onDisconnect:', error);
        }
        this.userRef = null;
      }

      if (this.connectedRef) {
        this.connectedRef = null;
      }

      if (this.retryTimeout) {
        clearTimeout(this.retryTimeout);
        this.retryTimeout = null;
      }

      if (this.awayTimeout) {
        clearTimeout(this.awayTimeout);
        this.awayTimeout = null;
      }

      this.connectionStatus.isConnected = false;
      this.connectionStatus.retryCount = 0;
      this.notifyConnectionListeners();
      
    } catch (error) {
      this.logError('Error during cleanup:', error);
    }
  }

  public subscribeToConnectionStatus(callback: (status: ConnectionStatus) => void): () => void {
    this.log("Subscribing to connection status");
    
    this.initialize().catch(this.logError);
    this.listeners.add(callback);
    
    callback(this.connectionStatus);
    
    return () => {
      this.listeners.delete(callback);
    };
  }

  private notifyConnectionListeners() {
    this.log('Notifying connection listeners:', this.connectionStatus.isConnected, 'listeners count:', this.listeners.size);
    this.listeners.forEach(callback => {
      try {
        callback(this.connectionStatus);
      } catch (error) {
        this.logError('Error in connection listener callback:', error);
      }
    });
  }

  public subscribeToUserPresence(
    uid: string,
    callback: (presence: PresenceState | null) => void
  ): () => void {
    this.initialize().catch(this.logError);
    
    if (!this.config.database) {
      this.logError('Database not initialized');
      return () => {};
    }

    try {
      const userPresenceRef = ref(this.config.database, `${this.config.databasePath}/${uid}`);
      
      if (!this.presenceListeners.has(uid)) {
        this.presenceListeners.set(uid, new Set());
      }
      this.presenceListeners.get(uid)!.add(callback);

      const unsubscribe = onValue(userPresenceRef, (snapshot) => {
        const presence = snapshot.val() as PresenceState | null;
        callback(presence);
      }, (error) => {
        this.logError('Error in user presence listener:', error);
        callback(null);
      });

      return () => {
        unsubscribe();
        const userListeners = this.presenceListeners.get(uid);
        if (userListeners) {
          userListeners.delete(callback);
          if (userListeners.size === 0) {
            this.presenceListeners.delete(uid);
          }
        }
      };
    } catch (error) {
      this.logError('Error subscribing to user presence:', error);
      return () => {};
    }
  }

  public getConnectionStatus(): ConnectionStatus {
    return { ...this.connectionStatus };
  }

  public getCurrentPresenceState(): PresenceState['state'] {
    return this.currentPresenceState;
  }

  public async setCustomPresenceState(
    state: PresenceState['state'],
    customData?: Record<string, any>
  ): Promise<void> {
    return this.setPresenceState(state, customData);
  }

  public async goOnline(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('online', customData);
  }

  public async goOffline(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('offline', customData);
  }

  public async setAway(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('away', customData);
  }

  public async setBusy(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('busy', customData);
  }

  public getDebugInfo() {
    return {
      initialized: this.initialized,
      currentUser: this.currentUser?.uid,
      userRef: !!this.userRef,
      connectedRef: !!this.connectedRef,
      connectionStatus: this.connectionStatus,
      setupInProgress: this.setupInProgress,
      currentSetupUid: this.currentSetupUid,
      listenersCount: this.listeners.size,
      presenceListenersCount: this.presenceListeners.size,
      currentPresenceState: this.currentPresenceState,
      config: {
        ...this.config,
        firebaseApp: !!this.config.firebaseApp,
        database: !!this.config.database,
        auth: !!this.config.auth
      }
    };
  }

  public updateConfig(newConfig: Partial<PresenceConfig>): void {
    this.config = { ...this.config, ...newConfig } as Required<PresenceConfig>;
    this.log('Config updated:', newConfig);
  }

  public destroy(): void {
    if (this.authUnsubscribe) {
      this.authUnsubscribe();
      this.authUnsubscribe = null;
    }
    if (this.appStateUnsubscribe) {
      this.appStateUnsubscribe();
      this.appStateUnsubscribe = null;
    }
    this.cleanup();
    this.listeners.clear();
    this.presenceListeners.clear();
    this.initialized = false;
    this.initPromise = null;
  }
}
EOF
print_status "PresenceService created"

# 4. Create React Context
echo -e "${YELLOW}Creating React Context...${NC}"
cat > src/context/PresenceContext.tsx << 'EOF'
import React, { createContext, useContext, useEffect, useRef, ReactNode } from 'react';
import { PresenceService } from '../PresenceService';
import { PresenceConfig, PresenceError } from '../types';

interface PresenceContextValue {
  presenceService: PresenceService;
}

const PresenceContext = createContext<PresenceContextValue | null>(null);

interface PresenceProviderProps {
  children: ReactNode;
  config: PresenceConfig;
}

export const PresenceProvider: React.FC<PresenceProviderProps> = ({ 
  children, 
  config 
}) => {
  const presenceServiceRef = useRef<PresenceService | null>(null);

  if (!presenceServiceRef.current) {
    try {
      presenceServiceRef.current = new PresenceService(config);
    } catch (error) {
      console.error('Failed to initialize PresenceService:', error);
      throw error;
    }
  }

  useEffect(() => {
    if (presenceServiceRef.current) {
      presenceServiceRef.current.updateConfig(config);
    }
  }, [config]);

  useEffect(() => {
    return () => {
      if (presenceServiceRef.current) {
        presenceServiceRef.current.destroy();
        presenceServiceRef.current = null;
      }
    };
  }, []);

  const contextValue: PresenceContextValue = {
    presenceService: presenceServiceRef.current
  };

  return (
    <PresenceContext.Provider value={contextValue}>
      {children}
    </PresenceContext.Provider>
  );
};

export const usePresenceContext = (): PresenceContextValue => {
  const context = useContext(PresenceContext);
  if (!context) {
    throw new PresenceError(
      'usePresenceContext must be used within a PresenceProvider',
      'MISSING_PROVIDER'
    );
  }
  return context;
};
EOF
print_status "React Context created"

# 5. Create React hooks
echo -e "${YELLOW}Creating React hooks...${NC}"

# Connection Status Hook
cat > src/hooks/useConnectionStatus.ts << 'EOF'
import { useState, useEffect } from 'react';
import { ConnectionStatus } from '../types';
import { usePresenceContext } from '../context/PresenceContext';

export interface UseConnectionStatusReturn {
  isConnected: boolean;
  lastConnected: Date | null;
  retryCount: number;
  connectionStatus: ConnectionStatus;
}

export const useConnectionStatus = (): UseConnectionStatusReturn => {
  const { presenceService } = usePresenceContext();
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>(() =>
    presenceService.getConnectionStatus()
  );

  useEffect(() => {
    const unsubscribe = presenceService.subscribeToConnectionStatus(
      (status: ConnectionStatus) => {
        setConnectionStatus(status);
      }
    );

    return unsubscribe;
  }, [presenceService]);

  return {
    isConnected: connectionStatus.isConnected,
    lastConnected: connectionStatus.lastConnected,
    retryCount: connectionStatus.retryCount,
    connectionStatus
  };
};
EOF

# Main Presence Hook
cat > src/hooks/usePresence.ts << 'EOF'
import { useState, useCallback } from 'react';
import { PresenceState } from '../types';
import { usePresenceContext } from '../context/PresenceContext';
import { useConnectionStatus } from './useConnectionStatus';

export interface UsePresenceReturn {
  currentState: PresenceState['state'];
  isConnected: boolean;
  setOnline: (customData?: Record<string, any>) => Promise<void>;
  setOffline: (customData?: Record<string, any>) => Promise<void>;
  setAway: (customData?: Record<string, any>) => Promise<void>;
  setBusy: (customData?: Record<string, any>) => Promise<void>;
  setCustomState: (state: PresenceState['state'], customData?: Record<string, any>) => Promise<void>;
}

export const usePresence = (): UsePresenceReturn => {
  const { presenceService } = usePresenceContext();
  const { isConnected } = useConnectionStatus();
  const [currentState, setCurrentState] = useState<PresenceState['state']>(
    () => presenceService.getCurrentPresenceState()
  );

  const setOnline = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.goOnline(customData);
      setCurrentState('online');
    } catch (error) {
      console.error('Failed to set online:', error);
      throw error;
    }
  }, [presenceService]);

  const setOffline = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.goOffline(customData);
      setCurrentState('offline');
    } catch (error) {
      console.error('Failed to set offline:', error);
      throw error;
    }
  }, [presenceService]);

  const setAway = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.setAway(customData);
      setCurrentState('away');
    } catch (error) {
      console.error('Failed to set away:', error);
      throw error;
    }
  }, [presenceService]);

  const setBusy = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.setBusy(customData);
      setCurrentState('busy');
    } catch (error) {
      console.error('Failed to set busy:', error);
      throw error;
    }
  }, [presenceService]);

  const setCustomState = useCallback(async (
    state: PresenceState['state'],
    customData?: Record<string, any>
  ) => {
    try {
      await presenceService.setCustomPresenceState(state, customData);
      setCurrentState(state);
    } catch (error) {
      console.error('Failed to set custom state:', error);
      throw error;
    }
  }, [presenceService]);

  return {
    currentState,
    isConnected,
    setOnline,
    setOffline,
    setAway,
    setBusy,
    setCustomState
  };
};
EOF

# User Presence Hook
cat > src/hooks/useUserPresence.ts << 'EOF'
import { useState, useEffect } from 'react';
import { PresenceState } from '../types';
import { usePresenceContext } from '../context/PresenceContext';

export interface UseUserPresenceReturn {
  presence: PresenceState | null;
  isOnline: boolean;
  isOffline: boolean;
  isAway: boolean;
  isBusy: boolean;
  lastSeen: Date | null;
  customData?: Record<string, any>;
}

export const useUserPresence = (userId: string): UseUserPresenceReturn => {
  const { presenceService } = usePresenceContext();
  const [presence, setPresence] = useState<PresenceState | null>(null);

  useEffect(() => {
    if (!userId) {
      setPresence(null);
      return;
    }

    const unsubscribe = presenceService.subscribeToUserPresence(
      userId,
      (userPresence: PresenceState | null) => {
        setPresence(userPresence);
      }
    );

    return unsubscribe;
  }, [userId, presenceService]);

  const lastSeen = presence?.lastChanged 
    ? new Date(presence.lastChanged) 
    : null;

  return {
    presence,
    isOnline: presence?.state === 'online',
    isOffline: presence?.state === 'offline',
    isAway: presence?.state === 'away',
    isBusy: presence?.state === 'busy',
    lastSeen,
    customData: presence?.customData
  };
};
EOF

# Multiple Users Presence Hook
cat > src/hooks/useMultipleUsersPresence.ts << 'EOF'
import { useState, useEffect } from 'react';
import { PresenceState } from '../types';
import { usePresenceContext } from '../context/PresenceContext';

export interface MultipleUsersPresence {
  [userId: string]: PresenceState | null;
}

export interface UseMultipleUsersPresenceReturn {
  presences: MultipleUsersPresence;
  onlineUsers: string[];
  offlineUsers: string[];
  awayUsers: string[];
  busyUsers: string[];
  getPresence: (userId: string) => PresenceState | null;
  isUserOnline: (userId: string) => boolean;
}

export const useMultipleUsersPresence = (userIds: string[]): UseMultipleUsersPresenceReturn => {
  const { presenceService } = usePresenceContext();
  const [presences, setPresences] = useState<MultipleUsersPresence>({});

  useEffect(() => {
    const unsubscribeFunctions: Array<() => void> = [];
    const newPresences: MultipleUsersPresence = {};

    userIds.forEach(userId => {
      if (!userId) return;
      
      newPresences[userId] = null;
      
      const unsubscribe = presenceService.subscribeToUserPresence(
        userId,
        (presence: PresenceState | null) => {
          setPresences(prev => ({
            ...prev,
            [userId]: presence
          }));
        }
      );
      
      unsubscribeFunctions.push(unsubscribe);
    });

    setPresences(newPresences);

    return () => {
      unsubscribeFunctions.forEach(unsubscribe => unsubscribe());
    };
  }, [userIds, presenceService]);

  const onlineUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'online')
    .map(([userId]) => userId);

  const offlineUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'offline')
    .map(([userId]) => userId);

  const awayUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'away')
    .map(([userId]) => userId);

  const busyUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'busy')
    .map(([userId]) => userId);

  const getPresence = (userId: string): PresenceState | null => {
    return presences[userId] || null;
  };

  const isUserOnline = (userId: string): boolean => {
    return presences[userId]?.state === 'online';
  };

  return {
    presences,
    onlineUsers,
    offlineUsers,
    awayUsers,
    busyUsers,
    getPresence,
    isUserOnline
  };
};
EOF

# Debug Hook
cat > src/hooks/usePresenceDebug.ts << 'EOF'
import { useState, useEffect } from 'react';
import { usePresenceContext } from '../context/PresenceContext';

export interface DebugInfo {
  initialized: boolean;
  currentUser?: string;
  userRef: boolean;
  connectedRef: boolean;
  connectionStatus: any;
  setupInProgress: boolean;
  currentSetupUid?: string;
  listenersCount: number;
  presenceListenersCount: number;
  currentPresenceState: string;
  config: any;
}

export const usePresenceDebug = (): DebugInfo => {
  const { presenceService } = usePresenceContext();
  const [debugInfo, setDebugInfo] = useState<DebugInfo>(() => 
    presenceService.getDebugInfo()
  );

  useEffect(() => {
    const interval = setInterval(() => {
      setDebugInfo(presenceService.getDebugInfo());
    }, 1000);

    return () => clearInterval(interval);
  }, [presenceService]);

  return debugInfo;
};
EOF

print_status "React hooks created"

# 6. Create UI Components
echo -e "${YELLOW}Creating UI components...${NC}"

# Presence Indicator Component
cat > src/components/PresenceIndicator.tsx << 'EOF'
import React from 'react';
import { View, Text, StyleSheet, ViewStyle, TextStyle } from 'react-native';
import { useUserPresence } from '../hooks/useUserPresence';
import { PresenceState } from '../types';

interface PresenceIndicatorProps {
  userId: string;
  size?: 'small' | 'medium' | 'large';
  showStatus?: boolean;
  showLastSeen?: boolean;
  style?: ViewStyle;
  textStyle?: TextStyle;
  colors?: {
    online?: string;
    offline?: string;
    away?: string;
    busy?: string;
  };
}

const defaultColors = {
  online: '#4CAF50',
  offline: '#9E9E9E',
  away: '#FF9800',
  busy: '#F44336'
};

const sizes = {
  small: 8,
  medium: 12,
  large: 16
};

export const PresenceIndicator: React.FC<PresenceIndicatorProps> = ({
  userId,
  size = 'medium',
  showStatus = false,
  showLastSeen = false,
  style,
  textStyle,
  colors = defaultColors
}) => {
  const { presence, isOnline, lastSeen } = useUserPresence(userId);
  
  if (!presence) {
    return null;
  }

  const indicatorSize = sizes[size];
  const statusColor = colors[presence.state] || defaultColors[presence.state];

  const formatLastSeen = (date: Date | null): string => {
    if (!date) return 'Never';
    
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${days}d ago`;
  };

  return (
    <View style={[styles.container, style]}>
      <View
        style={[
          styles.indicator,
          {
            width: indicatorSize,
            height: indicatorSize,
            backgroundColor: statusColor,
            borderRadius: indicatorSize / 2
          }
        ]}
      />
      {showStatus && (
        <Text style={[styles.statusText, textStyle]}>
          {presence.state.charAt(0).toUpperCase() + presence.state.slice(1)}
        </Text>
      )}
      {showLastSeen && !isOnline && lastSeen && (
        <Text style={[styles.lastSeenText, textStyle]}>
          {formatLastSeen(lastSeen)}
        </Text>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center'
  },
  indicator: {
    marginRight: 6
  },
  statusText: {
    fontSize: 14,
    fontWeight: '500',
    marginRight: 8
  },
  lastSeenText: {
    fontSize: 12,
    color: '#666',
    fontStyle: 'italic'
  }
});
EOF

# Debug Panel Component
cat > src/components/PresenceDebugPanel.tsx << 'EOF'
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
EOF

# Component index
cat > src/components/index.ts << 'EOF'
export { PresenceIndicator } from './PresenceIndicator';
export { PresenceDebugPanel } from './PresenceDebugPanel';
EOF

print_status "UI components created"

# 7. Create configuration helpers
echo -e "${YELLOW}Creating configuration helpers...${NC}"
cat > src/config/index.ts << 'EOF'
import { PresenceService } from '../PresenceService';
import { PresenceConfig, PresenceError } from '../types';

let globalPresenceService: PresenceService | null = null;

/**
 * Configure a global presence service instance
 * This is useful for apps that want a singleton approach
 */
export function configurePresence(config: PresenceConfig): PresenceService {
  if (globalPresenceService) {
    console.warn('Global presence service already configured. Destroying previous instance.');
    globalPresenceService.destroy();
  }
  
  try {
    globalPresenceService = new PresenceService(config);
    return globalPresenceService;
  } catch (error) {
    throw new PresenceError(
      'Failed to configure global presence service',
      'CONFIG_FAILED',
      error as Error
    );
  }
}

/**
 * Get the global presence service instance
 */
export function getGlobalPresenceService(): PresenceService {
  if (!globalPresenceService) {
    throw new PresenceError(
      'Global presence service not configured. Call configurePresence() first.',
      'NOT_CONFIGURED'
    );
  }
  return globalPresenceService;
}

/**
 * Create a new presence service instance (non-global)
 */
export function createPresenceService(config: PresenceConfig): PresenceService {
  return new PresenceService(config);
}

/**
 * Destroy the global presence service
 */
export function destroyGlobalPresenceService(): void {
  if (globalPresenceService) {
    globalPresenceService.destroy();
    globalPresenceService = null;
  }
}
EOF
print_status "Configuration helpers created"

# 8. Update main index file
echo -e "${YELLOW}Updating main exports...${NC}"
cat > src/index.ts << 'EOF'
// Main exports
export { PresenceService } from './PresenceService';
export { PresenceProvider, usePresenceContext } from './context/PresenceContext';

// Hooks exports
export { useConnectionStatus } from './hooks/useConnectionStatus';
export { usePresence } from './hooks/usePresence';
export { useUserPresence } from './hooks/useUserPresence';
export { useMultipleUsersPresence } from './hooks/useMultipleUsersPresence';
export { usePresenceDebug } from './hooks/usePresenceDebug';

// Types exports
export {
  PresenceState,
  PresenceConfig,
  ConnectionStatus,
  PresenceError
} from './types';

// Utility exports
export { FirebaseValidator } from './utils/firebase';

// Configuration helper
export { configurePresence, createPresenceService } from './config';

// Components
export { PresenceIndicator, PresenceDebugPanel } from './components';
EOF
print_status "Main exports updated"

# 9. Create comprehensive tests
echo -e "${YELLOW}Creating comprehensive tests...${NC}"
cat > __tests__/PresenceService.test.ts << 'EOF'
import { PresenceService } from '../src/PresenceService';
import { PresenceError } from '../src/types';

// Mock Firebase
const mockFirebase = {
  auth: {
    onAuthStateChanged: jest.fn(),
    currentUser: null
  },
  database: {
    ref: jest.fn(),
    serverTimestamp: jest.fn(() => ({ '.sv': 'timestamp' })),
    set: jest.fn(),
    onValue: jest.fn(),
    onDisconnect: jest.fn(() => ({
      set: jest.fn(),
      cancel: jest.fn()
    }))
  }
};

describe('PresenceService', () => {
  let presenceService: PresenceService;

  beforeEach(() => {
    jest.clearAllMocks();
    presenceService = new PresenceService({
      firebaseApp: mockFirebase,
      database: mockFirebase.database,
      auth: mockFirebase.auth,
      debug: false
    });
  });

  afterEach(() => {
    if (presenceService) {
      presenceService.destroy();
    }
  });

  describe('Initialization', () => {
    it('should initialize with valid config', () => {
      expect(presenceService).toBeDefined();
    });

    it('should throw error with invalid config', () => {
      expect(() => {
        new PresenceService({});
      }).toThrow(PresenceError);
    });
  });

  describe('Connection Status', () => {
    it('should return initial connection status', () => {
      const status = presenceService.getConnectionStatus();
      expect(status.isConnected).toBe(false);
      expect(status.retryCount).toBe(0);
    });

    it('should subscribe to connection status changes', () => {
      const callback = jest.fn();
      const unsubscribe = presenceService.subscribeToConnectionStatus(callback);
      
      expect(callback).toHaveBeenCalledWith(
        expect.objectContaining({
          isConnected: false,
          retryCount: 0
        })
      );
      
      unsubscribe();
    });
  });

  describe('Debug Information', () => {
    it('should return debug info', () => {
      const debugInfo = presenceService.getDebugInfo();
      expect(debugInfo).toHaveProperty('initialized');
      expect(debugInfo).toHaveProperty('currentPresenceState');
      expect(debugInfo).toHaveProperty('connectionStatus');
    });
  });
});
EOF

# Update the main test to check all exports
cat > __tests__/index.test.ts << 'EOF'
import * as LibraryExports from '../src';

describe('Library Exports', () => {
  it('should export all required components', () => {
    expect(LibraryExports.PresenceService).toBeDefined();
    expect(LibraryExports.PresenceProvider).toBeDefined();
    expect(LibraryExports.usePresence).toBeDefined();
    expect(LibraryExports.useConnectionStatus).toBeDefined();
    expect(LibraryExports.useUserPresence).toBeDefined();
    expect(LibraryExports.useMultipleUsersPresence).toBeDefined();
    expect(LibraryExports.usePresenceDebug).toBeDefined();
    expect(LibraryExports.PresenceIndicator).toBeDefined();
    expect(LibraryExports.PresenceDebugPanel).toBeDefined();
    expect(LibraryExports.PresenceError).toBeDefined();
    expect(LibraryExports.FirebaseValidator).toBeDefined();
    expect(LibraryExports.configurePresence).toBeDefined();
    expect(LibraryExports.createPresenceService).toBeDefined();
  });
  
  it('should export types correctly', () => {
    expect(LibraryExports.PresenceError).toBeDefined();
    expect(() => new LibraryExports.PresenceError('test', 'TEST_CODE')).not.toThrow();
  });
});
EOF

print_status "Tests updated"

# 10. Create example app structure
echo -e "${YELLOW}Creating example app...${NC}"
mkdir -p example/src

cat > example/package.json << 'EOF'
{
  "name": "react-native-firebase-presence-example",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "react-native start",
    "android": "react-native run-android",
    "ios": "react-native run-ios",
    "test": "jest"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-native": "^0.72.0",
    "firebase": "^9.22.0",
    "react-native-firebase-presence": "file:.."
  },
  "devDependencies": {
    "@types/react": "^18.0.0",
    "@types/react-native": "^0.70.0"
  }
}
EOF

cat > example/App.tsx << 'EOF'
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
EOF

print_status "Example app created"

# 11. Try to build and test
echo -e "${YELLOW}Building and testing implementation...${NC}"

if npm run build 2>/dev/null; then
    print_status "Build successful!"
else
    print_warning "Build failed - you may need to fix TypeScript errors"
fi

if npm test 2>/dev/null; then
    print_status "Tests passed!"
else
    print_warning "Some tests failed - you may need to fix them"
fi

# 12. Final summary and instructions
echo ""
echo -e "${GREEN}🎉 Library implementation completed!${NC}"
echo ""
echo -e "${BLUE}📋 Implementation Summary:${NC}"
echo -e "${YELLOW}✅ Core PresenceService with full functionality${NC}"
echo -e "${YELLOW}✅ React Context and Provider${NC}"
echo -e "${YELLOW}✅ 5 React Hooks for different use cases${NC}"
echo -e "${YELLOW}✅ 2 UI Components (Indicator & Debug Panel)${NC}"
echo -e "${YELLOW}✅ Configuration helpers${NC}"
echo -e "${YELLOW}✅ Comprehensive TypeScript types${NC}"
echo -e "${YELLOW}✅ Firebase utilities${NC}"
echo -e "${YELLOW}✅ Test files${NC}"
echo -e "${YELLOW}✅ Example app${NC}"
echo ""
echo -e "${BLUE}📁 Files Created/Updated:${NC}"
echo "  src/types/index.ts"
echo "  src/utils/firebase.ts"
echo "  src/PresenceService.ts"
echo "  src/context/PresenceContext.tsx"
echo "  src/hooks/ (5 hook files)"
echo "  src/components/ (2 component files + index)"
echo "  src/config/index.ts"
echo "  src/index.ts"
echo "  __tests__/ (test files updated)"
echo "  example/ (complete example app)"
echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. ${YELLOW}Fix any TypeScript/build errors:${NC}"
echo "   npm run build"
echo ""
echo "2. ${YELLOW}Run tests to make sure everything works:${NC}"
echo "   npm test"
echo ""
echo "3. ${YELLOW}Test with linter:${NC}"
echo "   npm run lint"
echo ""
echo "4. ${YELLOW}Set up your Firebase configuration in example/App.tsx${NC}"
echo ""
echo "5. ${YELLOW}Commit and push to GitHub:${NC}"
echo "   git add ."
echo "   git commit -m \"feat: complete library implementation with all features\""
echo "   git push origin main"
echo ""
echo "6. ${YELLOW}Test the CI/CD pipeline by creating a pull request${NC}"
echo ""
echo "7. ${YELLOW}Create your first release:${NC}"
echo "   ./scripts/release.sh"
echo ""
echo -e "${GREEN}🎯 Your React Native Firebase Presence library is now fully implemented!${NC}"
echo ""

# 13. Create a verification script
cat > scripts/verify-implementation.sh << 'EOF'
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
EOF

chmod +x scripts/verify-implementation.sh

print_status "Verification script created"

echo ""
echo -e "${BLUE}💡 Pro Tip: Run the verification script to check everything:${NC}"
echo "   ./scripts/verify-implementation.sh"
echo ""#!/bin/bash

# implement-library.sh - Complete Library Implementation
# Run this AFTER the setup-repo.sh script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Implementing React Native Firebase Presence Library...${NC}"
echo ""

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo -e "${RED}❌ package.json not found. Make sure you're in the library root directory.${NC}"
    exit 1
fi

# Check if this looks like our library
if ! grep -q "react-native-firebase-presence" package.json; then
    print_warning "This doesn't look like the Firebase Presence library directory. Continuing anyway..."
fi

echo -e "${BLUE}📝 Creating complete library implementation...${NC}"

# 1. Create complete types
echo -e "${YELLOW}Creating types...${NC}"
cat > src/types/index.ts << 'EOF'
export interface PresenceState {
  state: 'online' | 'offline' | 'away' | 'busy';
  lastChanged: any;
  customData?: Record<string, any>;
  uid?: string;
}

export interface PresenceConfig {
  firebaseApp?: any;
  database?: any;
  auth?: any;
  databasePath?: string;
  offlineTimeout?: number;
  retryInterval?: number;
  maxRetries?: number;
  debug?: boolean;
  customStates?: string[];
  autoSetAway?: boolean;
  awayTimeout?: number;
}

export interface ConnectionStatus {
  isConnected: boolean;
  lastConnected: Date | null;
  retryCount: number;
}

export class PresenceError extends Error {
  constructor(
    message: string,
    public code: string,
    public originalError?: Error
  ) {
    super(message);
    this.name = 'PresenceError';
  }
}
EOF
print_status "Types created"

# 2. Create Firebase utilities
echo -e "${YELLOW}Creating Firebase utilities...${NC}"
cat > src/utils/firebase.ts << 'EOF'
import { PresenceConfig, PresenceError } from '../types';

export class FirebaseValidator {
  static validateConfig(config: PresenceConfig): void {
    if (!config.firebaseApp) {
      throw new PresenceError(
        'Firebase app is required',
        'MISSING_FIREBASE_APP'
      );
    }
    
    if (!config.database) {
      throw new PresenceError(
        'Firebase database is required',
        'MISSING_DATABASE'
      );
    }
    
    if (!config.auth) {
      throw new PresenceError(
        'Firebase auth is required',
        'MISSING_AUTH'
      );
    }
  }

  static createRetryDelay(attempt: number, baseDelay: number = 1000): number {
    return Math.min(baseDelay * Math.pow(2, attempt), 30000);
  }
}
EOF
print_status "Firebase utilities created"

# 3. Create PresenceService (first part - it's long so we'll split it)
echo -e "${YELLOW}Creating PresenceService...${NC}"
cat > src/PresenceService.ts << 'EOF'
import { AppState, AppStateStatus } from 'react-native';
import { onAuthStateChanged, User } from 'firebase/auth';
import { onDisconnect, onValue, ref, serverTimestamp, set } from 'firebase/database';
import { PresenceState, PresenceConfig, ConnectionStatus, PresenceError } from './types';
import { FirebaseValidator } from './utils/firebase';

export class PresenceService {
  private config: Required<PresenceConfig>;
  private userRef: any = null;
  private connectedRef: any = null;
  private connectedListener: (() => void) | null = null;
  private connectionStatus: ConnectionStatus = {
    isConnected: false,
    lastConnected: null,
    retryCount: 0
  };
  private currentUser: User | null = null;
  private listeners: Set<(status: ConnectionStatus) => void> = new Set();
  private presenceListeners: Map<string, Set<(presence: PresenceState | null) => void>> = new Map();
  private authUnsubscribe: (() => void) | null = null;
  private appStateUnsubscribe: any = null;
  private initialized = false;
  private initPromise: Promise<void> | null = null;
  private setupInProgress = false;
  private currentSetupUid: string | null = null;
  private retryTimeout: NodeJS.Timeout | null = null;
  private awayTimeout: NodeJS.Timeout | null = null;
  private currentPresenceState: PresenceState['state'] = 'offline';

  constructor(config: PresenceConfig = {}) {
    this.config = {
      databasePath: 'presence',
      offlineTimeout: 30000,
      retryInterval: 1000,
      maxRetries: 5,
      debug: false,
      customStates: ['online', 'offline', 'away', 'busy'],
      autoSetAway: true,
      awayTimeout: 300000,
      ...config
    } as Required<PresenceConfig>;

    this.initialize();
  }

  private log(...args: any[]) {
    if (this.config.debug) {
      console.log('[PresenceService]', ...args);
    }
  }

  private logError(...args: any[]) {
    if (this.config.debug) {
      console.error('[PresenceService]', ...args);
    }
  }

  private async initialize() {
    if (this.initPromise) return this.initPromise;
    
    this.initPromise = this._initialize();
    return this.initPromise;
  }

  private async _initialize() {
    if (this.initialized) return;
    
    try {
      this.log('Initializing presence service...');
      
      FirebaseValidator.validateConfig(this.config);
      
      if (!this.config.auth || !this.config.database) {
        throw new PresenceError(
          'Firebase services not ready',
          'SERVICES_NOT_READY'
        );
      }

      this.initialized = true;
      this.log('Presence service initialized');
      
      this.authUnsubscribe = onAuthStateChanged(this.config.auth, (user) => {
        this.handleAuthStateChange(user);
      });

      this.setupAppStateListener();
      
    } catch (error) {
      this.logError('Error initializing presence service:', error);
      this.initialized = false;
      this.initPromise = null;
      throw error instanceof PresenceError ? error : new PresenceError(
        'Failed to initialize presence service',
        'INIT_FAILED',
        error as Error
      );
    }
  }

  private handleAuthStateChange(user: User | null) {
    this.log('Auth state changed:', {
      newUid: user?.uid,
      previousUid: this.currentUser?.uid,
      currentSetupUid: this.currentSetupUid
    });
    
    if (user && user.uid !== this.currentSetupUid) {
      this.currentUser = user;
      this.currentSetupUid = user.uid;
      this.setupPresence(user.uid);
    } else if (!user) {
      this.currentSetupUid = null;
      if (this.currentUser) {
        this.log('User signed out, cleaning up');
        this.cleanup();
        this.currentUser = null;
      }
    }
  }

  private setupAppStateListener() {
    this.appStateUnsubscribe = AppState.addEventListener('change', (nextAppState: AppStateStatus) => {
      this.log('App state changed:', nextAppState, 'Current user:', this.currentUser?.uid);
      
      if (this.currentUser && this.userRef) {
        this.handleAppStateChange(nextAppState);
      }
    });
  }

  private handleAppStateChange(appState: AppStateStatus) {
    if (this.awayTimeout) {
      clearTimeout(this.awayTimeout);
      this.awayTimeout = null;
    }

    switch (appState) {
      case 'active':
        this.log('App became active, setting online');
        this.setPresenceState('online');
        this.setupAwayTimer();
        break;
      case 'background':
      case 'inactive':
        this.log('App went to background, setting offline');
        this.setPresenceState('offline');
        break;
    }
  }

  private setupAwayTimer() {
    if (!this.config.autoSetAway) return;

    this.awayTimeout = setTimeout(() => {
      if (this.currentPresenceState === 'online') {
        this.log('Auto-setting user to away due to inactivity');
        this.setPresenceState('away');
      }
    }, this.config.awayTimeout);
  }

  private async setupPresence(uid: string) {
    if (this.setupInProgress) {
      this.log('Setup already in progress, skipping');
      return;
    }
    
    this.setupInProgress = true;
    
    try {
      this.log('Setting up presence for user:', uid);
      
      if (!this.config.database) {
        throw new PresenceError('Database not available', 'DATABASE_UNAVAILABLE');
      }
      
      this.cleanup();
      
      this.userRef = ref(this.config.database, `${this.config.databasePath}/${uid}`);
      this.connectedRef = ref(this.config.database, '.info/connected');

      this.log('UserRef created:', !!this.userRef);

      this.connectedListener = onValue(this.connectedRef, (snapshot) => {
        const connected = snapshot.val();
        this.handleConnectionChange(connected);
      }, (error) => {
        this.logError('Connection listener error:', error);
        this.handleConnectionError(error);
      });

      if (this.userRef) {
        this.log('Setting initial online status');
        await this.setPresenceState('online');
        this.setupAwayTimer();
      }
      
    } catch (error) {
      this.logError('Error setting up presence:', error);
      this.userRef = null;
      this.handleSetupError(error);
    } finally {
      this.setupInProgress = false;
    }
  }

  private handleConnectionChange(connected: boolean) {
    this.log('Connection status changed:', connected);
    
    const wasConnected = this.connectionStatus.isConnected;
    this.connectionStatus.isConnected = connected;
    
    if (connected) {
      this.connectionStatus.lastConnected = new Date();
      this.connectionStatus.retryCount = 0;
      
      if (!wasConnected && this.userRef) {
        this.setPresenceState(this.currentPresenceState || 'online');
      }
    }
    
    this.notifyConnectionListeners();
    
    if (!connected) {
      this.scheduleRetry();
    }
  }

  private handleConnectionError(error: any) {
    this.connectionStatus.retryCount++;
    this.logError('Connection error, retry count:', this.connectionStatus.retryCount, error);
    this.scheduleRetry();
  }

  private handleSetupError(error: any) {
    this.connectionStatus.retryCount++;
    if (this.connectionStatus.retryCount < this.config.maxRetries) {
      this.scheduleRetry();
    } else {
      this.logError('Max retries reached, giving up');
    }
  }

  private scheduleRetry() {
    if (this.retryTimeout || this.connectionStatus.retryCount >= this.config.maxRetries) {
      return;
    }

    const delay = FirebaseValidator.createRetryDelay(
      this.connectionStatus.retryCount,
      this.config.retryInterval
    );

    this.log(`Scheduling retry in ${delay}ms (attempt ${this.connectionStatus.retryCount + 1})`);

    this.retryTimeout = setTimeout(() => {
      this.retryTimeout = null;
      if (this.currentUser && !this.connectionStatus.isConnected) {
        this.setupPresence(this.currentUser.uid);
      }
    }, delay);
  }

  public async setPresenceState(
    state: PresenceState['state'],
    customData?: Record<string, any>
  ): Promise<void> {
    if (!this.userRef) {
      this.log('Cannot set presence state: userRef is null');
      return;
    }

    if (!this.currentUser) {
      this.log('Cannot set presence state: no current user');
      return;
    }

    if (!this.config.customStates.includes(state)) {
      throw new PresenceError(
        `Invalid presence state: ${state}`,
        'INVALID_STATE'
      );
    }

    this.log('Setting user presence state:', state);
    this.currentPresenceState = state;

    try {
      const presenceData: PresenceState = {
        state,
        lastChanged: serverTimestamp(),
        uid: this.currentUser.uid,
        ...(customData && { customData })
      };

      await set(this.userRef, presenceData);
      this.log('Successfully set presence state:', state);

      if (state === 'online') {
        await onDisconnect(this.userRef).set({
          state: 'offline' as const,
          lastChanged: serverTimestamp(),
          uid: this.currentUser.uid,
          ...(customData && { customData })
        });
        this.log('OnDisconnect handler set');
      }
      
    } catch (error) {
      this.logError('Error setting presence state:', error);
      throw new PresenceError(
        'Failed to set presence state',
        'SET_STATE_FAILED',
        error as Error
      );
    }
  }

  private cleanup() {
    try {
      this.log('Cleaning up presence service');
      
      if (this.connectedListener) {
        this.log('Removing connection listener');
        this.connectedListener();
        this.connectedListener = null;
      }

      if (this.userRef) {
        this.log('Cleaning up userRef and onDisconnect');
        try {
          onDisconnect(this.userRef).cancel();
        } catch (error) {
          this.logError('Error canceling onDisconnect:', error);
        }
        this.userRef = null;
      }

      if (this.connectedRef) {
        this.connectedRef = null;
      }

      if (this.retryTimeout) {
        clearTimeout(this.retryTimeout);
        this.retryTimeout = null;
      }

      if (this.awayTimeout) {
        clearTimeout(this.awayTimeout);
        this.awayTimeout = null;
      }

      this.connectionStatus.isConnected = false;
      this.connectionStatus.retryCount = 0;
      this.notifyConnectionListeners();
      
    } catch (error) {
      this.logError('Error during cleanup:', error);
    }
  }

  public subscribeToConnectionStatus(callback: (status: ConnectionStatus) => void): () => void {
    this.log("Subscribing to connection status");
    
    this.initialize().catch(this.logError);
    this.listeners.add(callback);
    
    callback(this.connectionStatus);
    
    return () => {
      this.listeners.delete(callback);
    };
  }

  private notifyConnectionListeners() {
    this.log('Notifying connection listeners:', this.connectionStatus.isConnected, 'listeners count:', this.listeners.size);
    this.listeners.forEach(callback => {
      try {
        callback(this.connectionStatus);
      } catch (error) {
        this.logError('Error in connection listener callback:', error);
      }
    });
  }

  public subscribeToUserPresence(
    uid: string,
    callback: (presence: PresenceState | null) => void
  ): () => void {
    this.initialize().catch(this.logError);
    
    if (!this.config.database) {
      this.logError('Database not initialized');
      return () => {};
    }

    try {
      const userPresenceRef = ref(this.config.database, `${this.config.databasePath}/${uid}`);
      
      if (!this.presenceListeners.has(uid)) {
        this.presenceListeners.set(uid, new Set());
      }
      this.presenceListeners.get(uid)!.add(callback);

      const unsubscribe = onValue(userPresenceRef, (snapshot) => {
        const presence = snapshot.val() as PresenceState | null;
        callback(presence);
      }, (error) => {
        this.logError('Error in user presence listener:', error);
        callback(null);
      });

      return () => {
        unsubscribe();
        const userListeners = this.presenceListeners.get(uid);
        if (userListeners) {
          userListeners.delete(callback);
          if (userListeners.size === 0) {
            this.presenceListeners.delete(uid);
          }
        }
      };
    } catch (error) {
      this.logError('Error subscribing to user presence:', error);
      return () => {};
    }
  }

  public getConnectionStatus(): ConnectionStatus {
    return { ...this.connectionStatus };
  }

  public getCurrentPresenceState(): PresenceState['state'] {
    return this.currentPresenceState;
  }

  public async setCustomPresenceState(
    state: PresenceState['state'],
    customData?: Record<string, any>
  ): Promise<void> {
    return this.setPresenceState(state, customData);
  }

  public async goOnline(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('online', customData);
  }

  public async goOffline(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('offline', customData);
  }

  public async setAway(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('away', customData);
  }

  public async setBusy(customData?: Record<string, any>): Promise<void> {
    return this.setPresenceState('busy', customData);
  }

  public getDebugInfo() {
    return {
      initialized: this.initialized,
      currentUser: this.currentUser?.uid,
      userRef: !!this.userRef,
      connectedRef: !!this.connectedRef,
      connectionStatus: this.connectionStatus,
      setupInProgress: this.setupInProgress,
      currentSetupUid: this.currentSetupUid,
      listenersCount: this.listeners.size,
      presenceListenersCount: this.presenceListeners.size,
      currentPresenceState: this.currentPresenceState,
      config: {
        ...this.config,
        firebaseApp: !!this.config.firebaseApp,
        database: !!this.config.database,
        auth: !!this.config.auth
      }
    };
  }

  public updateConfig(newConfig: Partial<PresenceConfig>): void {
    this.config = { ...this.config, ...newConfig } as Required<PresenceConfig>;
    this.log('Config updated:', newConfig);
  }

  public destroy(): void {
    if (this.authUnsubscribe) {
      this.authUnsubscribe();
      this.authUnsubscribe = null;
    }
    if (this.appStateUnsubscribe) {
      this.appStateUnsubscribe();
      this.appStateUnsubscribe = null;
    }
    this.cleanup();
    this.listeners.clear();
    this.presenceListeners.clear();
    this.initialized = false;
    this.initPromise = null;
  }
}
EOF
print_status "PresenceService created"

# 4. Create React Context
echo -e "${YELLOW}Creating React Context...${NC}"
cat > src/context/PresenceContext.tsx << 'EOF'
import React, { createContext, useContext, useEffect, useRef, ReactNode } from 'react';
import { PresenceService } from '../PresenceService';
import { PresenceConfig, PresenceError } from '../types';

interface PresenceContextValue {
  presenceService: PresenceService;
}

const PresenceContext = createContext<PresenceContextValue | null>(null);

interface PresenceProviderProps {
  children: ReactNode;
  config: PresenceConfig;
}

export const PresenceProvider: React.FC<PresenceProviderProps> = ({ 
  children, 
  config 
}) => {
  const presenceServiceRef = useRef<PresenceService | null>(null);

  if (!presenceServiceRef.current) {
    try {
      presenceServiceRef.current = new PresenceService(config);
    } catch (error) {
      console.error('Failed to initialize PresenceService:', error);
      throw error;
    }
  }

  useEffect(() => {
    if (presenceServiceRef.current) {
      presenceServiceRef.current.updateConfig(config);
    }
  }, [config]);

  useEffect(() => {
    return () => {
      if (presenceServiceRef.current) {
        presenceServiceRef.current.destroy();
        presenceServiceRef.current = null;
      }
    };
  }, []);

  const contextValue: PresenceContextValue = {
    presenceService: presenceServiceRef.current
  };

  return (
    <PresenceContext.Provider value={contextValue}>
      {children}
    </PresenceContext.Provider>
  );
};

export const usePresenceContext = (): PresenceContextValue => {
  const context = useContext(PresenceContext);
  if (!context) {
    throw new PresenceError(
      'usePresenceContext must be used within a PresenceProvider',
      'MISSING_PROVIDER'
    );
  }
  return context;
};
EOF
print_status "React Context created"

# 5. Create hooks (this will be a long section, so we'll create them one by one)
echo -e "${YELLOW}Creating React hooks...${NC}"

# Connection Status Hook
cat > src/hooks/use