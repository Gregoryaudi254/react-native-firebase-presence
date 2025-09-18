import React, { createContext, useContext, useEffect, useRef, ReactNode } from 'react';
import { PresenceService } from '../PresenceService';
import { PresenceConfig, PresenceError } from '../types';

interface PresenceContextValue {
  presenceService: PresenceService;
}

const PresenceContext = createContext<PresenceContextValue | null>(null);

interface PresenceProviderProps {
  children: ReactNode;
  config: PresenceConfig;
}

export const PresenceProvider: React.FC<PresenceProviderProps> = ({ 
  children, 
  config 
}) => {
  const presenceServiceRef = useRef<PresenceService | null>(null);

  if (!presenceServiceRef.current) {
    try {
      presenceServiceRef.current = new PresenceService(config);
    } catch (error) {
      console.error('Failed to initialize PresenceService:', error);
      throw error;
    }
  }

  useEffect(() => {
    if (presenceServiceRef.current) {
      presenceServiceRef.current.updateConfig(config);
    }
  }, [config]);

  useEffect(() => {
    return () => {
      if (presenceServiceRef.current) {
        presenceServiceRef.current.destroy();
        presenceServiceRef.current = null;
      }
    };
  }, []);

  const contextValue: PresenceContextValue = {
    presenceService: presenceServiceRef.current
  };

  return (
    <PresenceContext.Provider value={contextValue}>
      {children}
    </PresenceContext.Provider>
  );
};

export const usePresenceContext = (): PresenceContextValue => {
  const context = useContext(PresenceContext);
  if (!context) {
    throw new PresenceError(
      'usePresenceContext must be used within a PresenceProvider',
      'MISSING_PROVIDER'
    );
  }
  return context;
};
