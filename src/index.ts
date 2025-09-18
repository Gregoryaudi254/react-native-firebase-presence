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
