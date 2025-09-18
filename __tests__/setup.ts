// Mock React Native modules
jest.mock('react-native', () => ({
  AppState: {
    addEventListener: jest.fn(() => ({
      remove: jest.fn()
    })),
    currentState: 'active'
  }
}));

// Mock Firebase
jest.mock('firebase/auth', () => ({
  onAuthStateChanged: jest.fn(),
  getAuth: jest.fn()
}));

jest.mock('firebase/database', () => ({
  getDatabase: jest.fn(),
  ref: jest.fn(),
  onValue: jest.fn(),
  onDisconnect: jest.fn(() => ({
    set: jest.fn(),
    cancel: jest.fn()
  })),
  set: jest.fn(),
  serverTimestamp: jest.fn(() => ({ '.sv': 'timestamp' }))
}));

// Suppress console warnings in tests
global.console = {
  ...console,
  warn: jest.fn(),
  error: jest.fn()
};
