import * as React from 'react';
import { StaticField } from '../ui';
import { useTranslation } from '../../hooks';
import { TFunction } from 'i18next';
import { PlatformType } from '@openshift-assisted/types/assisted-installer-service';
import { Dropdown, DropdownItem, FormGroup, MenuToggle } from '@patternfly/react-core';
import { useField } from 'formik';

export const getPlatforms = (t: TFunction): { [key in PlatformType]: string } => ({
  none: t('ai:No platform integration'),
  baremetal: t('ai:No platform integration'),
  nutanix: t('ai:Nutanix'),
  vsphere: t('ai:vSphere'),
  external: t('ai:External cloud provider'),
});

export const ExternalPlatformsDropdown = ({ isDisabled }: { isDisabled: boolean }) => {
  const [isOpen, setIsOpen] = React.useState(false);
  const [{ value }, , { setValue }] = useField<PlatformType>('platform');
  const { t } = useTranslation();

  const platforms = getPlatforms(t);

  const options = Object.entries(platforms)
    .filter(([key]) => key !== 'none')
    .map(([platform, label]) => (
      <DropdownItem
        key={platform}
        id={platform}
        value={platform}
        selected={platform === value}
        onClick={(e: React.MouseEvent) => e.preventDefault()}
      >
        {label}
      </DropdownItem>
    ));

  const onSelect = (
    _event: React.MouseEvent<Element, MouseEvent> | undefined,
    value: string | number | undefined,
  ) => {
    setValue(value as PlatformType);
    setIsOpen(false);
  };

  return isDisabled ? (
    <StaticField
      name={'platform'}
      label={t('ai:Integrate with external partner platforms')}
      isRequired
    >
      {platforms[value]}
    </StaticField>
  ) : (
    <FormGroup
      isInline
      label={t('ai:Integrate with external partner platforms')}
      isRequired
      name={'platform'}
    >
      <Dropdown
        isOpen={isOpen}
        toggle={(toggleRef) => (
          <MenuToggle ref={toggleRef} className="pf-v5-u-w-100" onClick={() => setIsOpen(!isOpen)}>
            {value ? platforms[value] : t('ai:Integrate with external partner platforms')}
          </MenuToggle>
        )}
        onSelect={onSelect}
      >
        {options}
      </Dropdown>
    </FormGroup>
  );
};
