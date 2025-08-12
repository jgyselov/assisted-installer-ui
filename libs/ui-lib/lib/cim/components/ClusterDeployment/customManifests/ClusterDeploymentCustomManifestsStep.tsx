import React from 'react';
import Fuse from 'fuse.js';
import { k8sList, K8sResourceCommon } from '@openshift-console/dynamic-plugin-sdk';
import {
  Bullseye,
  Button,
  FormGroup,
  MenuToggle,
  MenuToggleElement,
  Select,
  SelectList,
  SelectOption,
  SelectOptionProps,
  Spinner,
  TextInputGroup,
  TextInputGroupMain,
  TextInputGroupUtilities,
} from '@patternfly/react-core';
import { Formik, useFormikContext } from 'formik';
import { TimesIcon } from '@patternfly/react-icons/dist/js/icons/times-icon';

// TODO: Create proper TypeScript interfaces for ConfigMap model
const model = {
  apiVersion: 'v1',
  label: 'ConfigMap',
  // t('public~ConfigMap')
  labelKey: 'public~ConfigMap',
  plural: 'configmaps',
  abbr: 'CM',
  namespaced: true,
  kind: 'ConfigMap',
  id: 'configmap',
  labelPlural: 'ConfigMaps',
  // t('public~ConfigMaps')
  labelPluralKey: 'public~ConfigMaps',
};

const NO_RESULTS = 'no_result';

const CustomManifestFormFields = () => {
  const [isLoading, setIsLoading] = React.useState(true);
  const [configMaps, setConfigMaps] = React.useState<SelectOptionProps[]>([]);
  const { values, setFieldValue } = useFormikContext<{
    configMaps: string[];
  }>();

  const [isOpen, setIsOpen] = React.useState(false);
  const [filter, setFilter] = React.useState<string>('');
  const [focusedItemIndex, setFocusedItemIndex] = React.useState<number | null>(null);
  const [activeItemId, setActiveItemId] = React.useState<string | null>(null);
  const textInputRef = React.useRef<HTMLInputElement>();

  const placeholder = React.useMemo(() => {
    if (values.configMaps.length > 0) {
      return `${values.configMaps.length} config map${
        values.configMaps.length !== 1 ? 's' : ''
      } selected`;
    }

    return 'No config map selected';
  }, [values.configMaps]);

  React.useEffect(() => {
    const get = async () => {
      try {
        const res = await k8sList<K8sResourceCommon>({
          model: model,
          queryParams: [],
        });

        setConfigMaps(
          res.map((configMap) => ({
            value: `${configMap.metadata?.name as string}_${
              configMap.metadata?.namespace as string
            }`,
            children: configMap.metadata?.name,
            description: `Namespace: ${configMap.metadata?.namespace as string}`,
            item: {
              namespace: configMap.metadata?.namespace as string,
              name: configMap.metadata?.name as string,
            },
          })),
        );
      } catch (error) {
        // TODO: Add proper error handling and user feedback
        console.error('Failed to fetch config maps:', error);
      } finally {
        setIsLoading(false);
      }
    };
    void get();
  }, []);

  const fuse = React.useMemo(
    () =>
      new Fuse(configMaps, {
        includeScore: true,
        ignoreLocation: true,
        threshold: 0.3,
        keys: ['item.name', 'item.namespace'],
      }),
    [configMaps],
  );

  const selectOptions = React.useMemo(() => {
    if (filter) {
      const newSelectOptions = fuse
        .search(filter)
        .sort((a, b) => (a.score || 0) - (b.score || 0))
        .map(({ item }) => item);

      if (!newSelectOptions.length) {
        return [
          {
            isAriaDisabled: true,
            children: `No results found for "${filter}"`,
            value: NO_RESULTS,
            hasCheckbox: false,
          },
        ];
      }

      return newSelectOptions;
    }

    return configMaps;
  }, [filter, configMaps, fuse]);

  // TODO: Fix type safety - replace 'any' with proper type
  const createItemId = (value: string) => `select-multi-typeahead-${value.replace(' ', '-')}`;

  const setActiveAndFocusedItem = (itemIndex: number) => {
    setFocusedItemIndex(itemIndex);
    const focusedItem = selectOptions[itemIndex];
    setActiveItemId(createItemId((focusedItem as { value: string }).value));
  };

  const resetActiveAndFocusedItem = () => {
    setFocusedItemIndex(null);
    setActiveItemId(null);
  };

  const closeMenu = () => {
    setIsOpen(false);
    resetActiveAndFocusedItem();
  };

  const onInputClick = () => {
    if (!isOpen) {
      setIsOpen(true);
    } else if (!filter) {
      closeMenu();
    }
  };

  const handleMenuArrowKeys = (key: string) => {
    let indexToFocus = 0;

    if (!isOpen) {
      setIsOpen(true);
    }

    if (key === 'ArrowUp') {
      if (focusedItemIndex === null || focusedItemIndex === 0) {
        indexToFocus = selectOptions.length - 1;
      } else {
        indexToFocus = focusedItemIndex - 1;
      }
    }

    if (key === 'ArrowDown') {
      // When no index is set or at the last index, focus to the first, otherwise increment focus index
      if (focusedItemIndex === null || focusedItemIndex === selectOptions.length - 1) {
        indexToFocus = 0;
      } else {
        indexToFocus = focusedItemIndex + 1;
      }
    }

    setActiveAndFocusedItem(indexToFocus);
  };

  const onInputKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    const focusedItem = focusedItemIndex !== null ? selectOptions[focusedItemIndex] : null;

    switch (event.key) {
      case 'Enter':
        if (
          isOpen &&
          focusedItem &&
          focusedItem.value !== NO_RESULTS &&
          !focusedItem.isAriaDisabled
        ) {
          // TODO: Fix type safety - ensure focusedItem.value is string
          onSelect(focusedItem.value as string);
        }

        if (!isOpen) {
          setIsOpen(true);
        }

        break;
      case 'ArrowUp':
      case 'ArrowDown':
        event.preventDefault();
        handleMenuArrowKeys(event.key);
        break;
    }
  };

  const onToggleClick = () => {
    setIsOpen(!isOpen);
    textInputRef?.current?.focus();
  };

  const onTextInputChange = (_event: React.FormEvent<HTMLInputElement>, value: string) => {
    setFilter(value);
    resetActiveAndFocusedItem();
  };

  const onSelect = (value: string) => {
    if (value && value !== NO_RESULTS) {
      setFieldValue(
        'configMaps',
        values.configMaps.includes(value)
          ? values.configMaps.filter((i) => i !== value)
          : [...values.configMaps, value],
      );
    }

    textInputRef.current?.focus();
  };

  const toggle = (toggleRef: React.Ref<MenuToggleElement>) => (
    <MenuToggle
      variant="typeahead"
      aria-label="Multi typeahead checkbox menu toggle"
      onClick={onToggleClick}
      innerRef={toggleRef}
      isExpanded={isOpen}
      isFullWidth
    >
      <TextInputGroup isPlain>
        <TextInputGroupMain
          value={filter}
          onClick={onInputClick}
          onChange={onTextInputChange}
          onKeyDown={onInputKeyDown}
          id="multi-typeahead-select-checkbox-input"
          autoComplete="off"
          innerRef={textInputRef}
          placeholder={placeholder}
          {...(activeItemId && { 'aria-activedescendant': activeItemId })}
          role="combobox"
          isExpanded={isOpen}
          aria-controls="select-multi-typeahead-checkbox-listbox"
        />
        <TextInputGroupUtilities style={filter ? {} : { display: 'none' }}>
          <Button variant="plain" onClick={() => setFilter('')} aria-label="Clear input value">
            <TimesIcon aria-hidden />
          </Button>
        </TextInputGroupUtilities>
      </TextInputGroup>
    </MenuToggle>
  );

  return (
    <>
      <FormGroup label="Select config maps" isRequired>
        <Select
          role="menu"
          isOpen={isOpen}
          selected={values.configMaps}
          onSelect={(_event, selection) => onSelect(selection as string)}
          onOpenChange={(isOpen) => {
            !isOpen && closeMenu();
          }}
          toggle={toggle}
          isScrollable
        >
          <SelectList key={`filter-${filter}`} isAriaMultiselectable>
            {isLoading ? (
              <SelectOption key={'loader'}>
                <Bullseye>
                  <Spinner size="lg" />
                </Bullseye>
              </SelectOption>
            ) : (
              selectOptions.map((option, index) => (
                <SelectOption
                  hasCheckbox
                  isSelected={values.configMaps.includes(option.value as string)}
                  key={option.value as string}
                  isFocused={focusedItemIndex === index}
                  className={option.className}
                  id={createItemId(option.value as string)}
                  {...option}
                  ref={null}
                />
              ))
            )}
          </SelectList>
        </Select>
      </FormGroup>
    </>
  );
};

export const ClusterDeploymentCustomManifestsStep = () => {
  const onSubmit = (values: { configMaps: string[] }) => {
    // TODO: Remove console.log from production code
    console.log(values);
  };

  return (
    <Formik initialValues={{ configMaps: [] as string[] }} onSubmit={onSubmit}>
      <CustomManifestFormFields />
    </Formik>
  );
};
