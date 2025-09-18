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
