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
