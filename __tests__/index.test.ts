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
