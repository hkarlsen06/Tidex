"use client";

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
  type ReactNode,
} from "react";

type ScrollDirection = "up" | "down" | null;

interface ScrollContextValue {
  /**
   * Register a scroll container element for the NavBar to observe.
   * Call with null to unregister when unmounting.
   */
  registerScrollContainer: (element: HTMLElement | null) => void;

  /**
   * Current scroll direction based on the registered container.
   * null if no container is registered or no scroll has occurred.
   */
  scrollDirection: ScrollDirection;
}

const ScrollContext = createContext<ScrollContextValue | null>(null);

interface ScrollProviderProps {
  children: ReactNode;
  /**
   * Minimum scroll distance (in px) required to trigger direction change.
   * Higher values make the navbar hide-on-scroll less sensitive.
   */
  threshold?: number;
}

export function ScrollProvider({
  children,
  threshold = 50,
}: ScrollProviderProps) {
  const [scrollContainer, setScrollContainer] = useState<HTMLElement | null>(
    null
  );
  const [scrollDirection, setScrollDirection] = useState<ScrollDirection>(null);
  const lastScrollY = useRef(0);
  const ticking = useRef(false);

  const registerScrollContainer = useCallback(
    (element: HTMLElement | null) => {
      setScrollContainer(element);
      // Reset scroll direction when container changes
      setScrollDirection(null);
      lastScrollY.current = element?.scrollTop ?? 0;
    },
    []
  );

  useEffect(() => {
    if (!scrollContainer) {
      return;
    }

    const updateScrollDirection = () => {
      const scrollY = scrollContainer.scrollTop;

      if (Math.abs(scrollY - lastScrollY.current) < threshold) {
        ticking.current = false;
        return;
      }

      setScrollDirection(scrollY > lastScrollY.current ? "down" : "up");
      lastScrollY.current = scrollY > 0 ? scrollY : 0;
      ticking.current = false;
    };

    const handleScroll = () => {
      if (!ticking.current) {
        window.requestAnimationFrame(updateScrollDirection);
        ticking.current = true;
      }
    };

    // Initialize last scroll position
    lastScrollY.current = scrollContainer.scrollTop;

    scrollContainer.addEventListener("scroll", handleScroll, { passive: true });

    return () => {
      scrollContainer.removeEventListener("scroll", handleScroll);
    };
  }, [scrollContainer, threshold]);

  return (
    <ScrollContext.Provider value={{ registerScrollContainer, scrollDirection }}>
      {children}
    </ScrollContext.Provider>
  );
}

export function useScrollContext() {
  const context = useContext(ScrollContext);
  if (!context) {
    throw new Error("useScrollContext must be used within a ScrollProvider");
  }
  return context;
}
