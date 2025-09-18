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
