import * as React from 'react';
import { Alert, AlertVariant, FlexItem, Form } from '@patternfly/react-core';
import { useFormikContext } from 'formik';

import { StaticTextField } from '../../../common/components/ui/StaticTextField';
import OpenShiftVersionSelect from '../../../common/components/clusterConfiguration/OpenShiftVersionSelect';
import { PullSecret } from '../../../common/components/clusters';
import { OpenshiftVersionOptionType } from '../../../common/types';
import {
  InputField,
  RichInputField,
  acmClusterNameValidationMessages,
} from '../../../common/components/ui/formik';
import { ClusterDetailsValues } from '../../../common/components/clusterWizard/types';
import { useTranslation } from '../../../common/hooks/use-translation-wrapper';
import CpuArchitectureDropdown from '../common/CpuArchitectureDropdown';
import { getNetworkType } from '../helpers';
import ControlPlaneNodesDropdown from '../../../common/components/clusterConfiguration/ControlPlaneNodesDropdown';
export type ClusterDetailsFormFieldsProps = {
  isEditFlow: boolean;
  forceOpenshiftVersion?: string;
  extensionAfter?: { [key: string]: React.ReactElement };
  versions: OpenshiftVersionOptionType[];
  isNutanix?: boolean;
  cpuArchitectures?: string[];
};

export const BaseDnsHelperText: React.FC<{ name?: string; baseDnsDomain?: string }> = ({
  name,
  baseDnsDomain,
}) => {
  const { t } = useTranslation();
  return (
    <>
      {t(
        'ai:All DNS records must be subdomains of this base and include the cluster name. This cannot be changed after cluster installation. The full cluster address will be:',
      )}{' '}
      <br />
      <strong>
        {name || '[Cluster Name]'}.{baseDnsDomain || '[example.com]'}
      </strong>
    </>
  );
};

export const ClusterDetailsFormFields: React.FC<ClusterDetailsFormFieldsProps> = ({
  isEditFlow,
  versions,
  forceOpenshiftVersion,
  extensionAfter,
  isNutanix,
  cpuArchitectures,
}) => {
  const { values, setFieldValue } = useFormikContext<ClusterDetailsValues>();
  const { name, baseDnsDomain } = values;

  const nameInputRef = React.useRef<HTMLInputElement>();
  React.useEffect(() => {
    nameInputRef.current?.focus();
  }, []);
  const atListOneDiskEncryptionEnableOn =
    values.enableDiskEncryptionOnMasters || values.enableDiskEncryptionOnWorkers;

  const { t } = useTranslation();
  return (
    <Form id="wizard-cluster-details__form">
      {isEditFlow ? (
        <StaticTextField name="name" label={t('ai:Cluster name')} isRequired>
          {name}
        </StaticTextField>
      ) : (
        <RichInputField
          ref={nameInputRef}
          label={t('ai:Cluster name')}
          name="name"
          placeholder={t('ai:Enter cluster name')}
          richValidationMessages={acmClusterNameValidationMessages(t)}
          isRequired
        />
      )}
      {extensionAfter?.['name'] && extensionAfter['name']}
      {isEditFlow ? (
        <StaticTextField
          name="baseDnsDomain"
          label={t('ai:Base domain')}
          helperText={<BaseDnsHelperText name={name} baseDnsDomain={baseDnsDomain} />}
          isRequired
        >
          {baseDnsDomain}
        </StaticTextField>
      ) : (
        <InputField
          label={t('ai:Base domain')}
          name="baseDnsDomain"
          helperText={<BaseDnsHelperText name={name} baseDnsDomain={baseDnsDomain} />}
          placeholder="example.com"
          isRequired
        />
      )}
      {forceOpenshiftVersion ? (
        <StaticTextField name="openshiftVersion" label="OpenShift version" isRequired>
          {t('ai:OpenShift')} {forceOpenshiftVersion}
        </StaticTextField>
      ) : (
        <OpenShiftVersionSelect
          versions={versions}
          onChange={(_event, value) => {
            const ocpVersion = versions.find((v) => v.value === value);
            setFieldValue('networkType', getNetworkType(ocpVersion));
          }}
        />
      )}
      <ControlPlaneNodesDropdown isNutanix={isNutanix} isDisabled={isEditFlow} />
      {!isNutanix && (
        <CpuArchitectureDropdown cpuArchitectures={cpuArchitectures} isDisabled={isEditFlow} />
      )}
      {extensionAfter?.['openshiftVersion'] && extensionAfter['openshiftVersion']}
      {!isEditFlow && <PullSecret />}
      {extensionAfter?.['pullSecret'] && extensionAfter['pullSecret']}
      {/* <DiskEncryptionControlGroup
        values={values}
        isDisabled={isPullSecretSet}
        isSNO={isSNO({ highAvailabilityMode })}
      /> */}
      {atListOneDiskEncryptionEnableOn && values.diskEncryptionMode === 'tpmv2' && (
        <Alert
          variant={AlertVariant.warning}
          isInline
          title={
            <FlexItem>
              {t(
                'ai:To use this encryption method, enable TPMv2 encryption in the BIOS of each selected host.',
              )}
            </FlexItem>
          }
        />
      )}
      {atListOneDiskEncryptionEnableOn && values.diskEncryptionMode === 'tang' && (
        <Alert
          variant={AlertVariant.warning}
          isInline
          title={
            <FlexItem>
              {t(
                'ai:The use of Tang encryption mode to encrypt your disks is only supported for bare metal or vSphere installations on user-provisioned infrastructure.',
              )}
            </FlexItem>
          }
        />
      )}
    </Form>
  );
};
