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
