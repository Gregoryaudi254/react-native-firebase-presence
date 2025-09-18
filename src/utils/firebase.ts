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
