import * as LibraryExports from '../src';

describe('Library Exports', () => {
  it('should export all required components', () => {
    expect(LibraryExports.PresenceService).toBeDefined();
    expect(LibraryExports.PresenceProvider).toBeDefined();
    expect(LibraryExports.usePresence).toBeDefined();
    expect(LibraryExports.useConnectionStatus).toBeDefined();
    expect(LibraryExports.useUserPresence).toBeDefined();
    expect(LibraryExports.PresenceError).toBeDefined();
  });
  
  it('should export types', () => {
    expect(LibraryExports.PresenceError).toBeDefined();
  });
});
