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
