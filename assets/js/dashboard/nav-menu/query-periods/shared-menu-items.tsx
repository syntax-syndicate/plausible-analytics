/** @format */

import React, {
  RefObject,
  useCallback,
  useEffect,
  useRef,
  useState
} from 'react'
import classNames from 'classnames'
import { popover } from '../../components/popover'
import { ChevronDownIcon } from '@heroicons/react/20/solid'
import { DashboardQuery } from '../../query'

export const linkClassName = classNames(
  popover.items.classNames.navigationLink,
  popover.items.classNames.selectedOption,
  popover.items.classNames.hoverLink,
  popover.items.classNames.roundedStartEnd
)

export const datemenuButtonClassName = classNames(
  popover.toggleButton.classNames.rounded,
  popover.toggleButton.classNames.shadow,
  'justify-between px-2 w-full'
)

export const DateMenuChevron = () => (
  <ChevronDownIcon className="hidden lg:inline-block h-4 w-4 md:h-5 md:w-5 ml-1 md:ml-2 text-gray-500" />
)

export const MenuSeparator = () => (
  <div className="my-1 border-gray-200 dark:border-gray-500 border-b" />
)

export interface PopoverMenuProps {
  dropdownIsOpen: boolean
  closeDropdown: () => void
}

export enum DropdownState {
  CLOSED = 'CLOSED',
  MENU = 'MENU',
  CALENDAR = 'CALENDAR'
}

export interface DropdownWithCalendarState {
  closeDropdown: () => void
  toggleDropdown: (mode: 'menu' | 'calendar') => void
  dropdownState: DropdownState
  buttonRef: RefObject<HTMLButtonElement>
}

export const useDropdownWithCalendar = ({
  query,
  closeDropdown,
  dropdownIsOpen
}: PopoverMenuProps & { query: DashboardQuery }): DropdownWithCalendarState => {
  const buttonRef = useRef<HTMLButtonElement>(null)
  const [currentMode, setCurrentMode] = useState<'menu' | 'calendar'>('menu')

  // closes dropdown when query changes
  useEffect(() => {
    closeDropdown()
  }, [closeDropdown, query])

  // resets dropdown to default mode 'menu' on close
  useEffect(() => {
    if (!dropdownIsOpen) {
      setCurrentMode('menu')
    }
  }, [dropdownIsOpen])

  const state: DropdownState = dropdownIsOpen
    ? currentMode === 'calendar'
      ? DropdownState.CALENDAR
      : DropdownState.MENU
    : DropdownState.CLOSED

  const toggleDropdown = useCallback(
    (mode: 'menu' | 'calendar') => {
      if (mode === currentMode) {
        closeDropdown()
        setCurrentMode('menu')
      } else {
        setCurrentMode(mode)
        if (mode === 'calendar' && !dropdownIsOpen) {
          buttonRef.current?.click()
        }
      }
    },
    [closeDropdown, currentMode, dropdownIsOpen]
  )

  return { buttonRef, dropdownState: state, closeDropdown, toggleDropdown }
}
