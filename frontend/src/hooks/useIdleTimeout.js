/**
 * useIdleTimeout - Custom hook for detecting user inactivity
 * 
 * Monitors user activity (mousemove, keydown, scroll, click, touchstart)
 * and triggers callback after specified timeout period.
 * 
 * @param {Function} onIdle - Callback function when user becomes idle
 * @param {number} timeout - Timeout in milliseconds (default: 2 hours = 7200000ms)
 * @returns {Object} - { isIdle, resetIdle, lastActivity }
 */

import { useEffect, useCallback, useRef, useState } from 'react';

// Default timeout: 2 hours in milliseconds
const DEFAULT_TIMEOUT = 2 * 60 * 60 * 1000; // 7200000ms

// Events that indicate user activity
const ACTIVITY_EVENTS = [
  'mousemove',
  'keydown',
  'scroll',
  'click',
  'touchstart',
  'touchmove',
  'MSPointerDown',
  'MSPointerMove',
  'visibilitychange',
  'focus'
];

export function useIdleTimeout(onIdle, timeout = DEFAULT_TIMEOUT) {
  // Track idle state
  const [isIdle, setIsIdle] = useState(false);
  
  // Track last activity timestamp
  const [lastActivity, setLastActivity] = useState(Date.now());
  
  // Timer reference
  const idleTimerRef = useRef(null);
  
  // Store callback in ref to avoid stale closures
  const onIdleRef = useRef(onIdle);
  
  // Update callback ref when it changes
  useEffect(() => {
    onIdleRef.current = onIdle;
  }, [onIdle]);
  
  // Reset idle timer
  const resetIdle = useCallback(() => {
    if (idleTimerRef.current) {
      clearTimeout(idleTimerRef.current);
    }
    
    setLastActivity(Date.now());
    setIsIdle(false);
    
    // Set new timer
    idleTimerRef.current = setTimeout(() => {
      setIsIdle(true);
      if (onIdleRef.current) {
        onIdleRef.current();
      }
    }, timeout);
  }, [timeout]);
  
  // Handle activity events
  const handleActivity = useCallback(() => {
    resetIdle();
  }, [resetIdle]);
  
  // Setup event listeners
  useEffect(() => {
    // Reset on mount
    resetIdle();
    
    // Add event listeners
    ACTIVITY_EVENTS.forEach(event => {
      window.addEventListener(event, handleActivity, { passive: true, capture: true });
    });
    
    // Cleanup
    return () => {
      if (idleTimerRef.current) {
        clearTimeout(idleTimerRef.current);
      }
      
      ACTIVITY_EVENTS.forEach(event => {
        window.removeEventListener(event, handleActivity, { capture: true });
      });
    };
  }, [handleActivity, resetIdle]);
  
  // Handle visibility change (tab switch)
  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        // User returned to tab, check if should still be active
        const timeSinceLastActivity = Date.now() - lastActivity;
        if (timeSinceLastActivity >= timeout) {
          setIsIdle(true);
          if (onIdleRef.current) {
            onIdleRef.current();
          }
        }
      }
    };
    
    document.addEventListener('visibilitychange', handleVisibilityChange);
    
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [lastActivity, timeout]);
  
  return {
    isIdle,
    resetIdle,
    lastActivity
  };
}

export default useIdleTimeout;
