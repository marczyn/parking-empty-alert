#!/bin/bash
# Converts Packer's qcow2 output to a standards-compliant OVA.
# Compatible with VMware ESXi, Synology VMM, and most other hypervisors.
#
# Usage: called as a Packer shell-local post-processor.
#   VARIANT, VERSION, VM_NAME must be set in the environment.
set -euo pipefail

VARIANT="${VARIANT}"
VERSION="${VERSION}"
VM_NAME="${VM_NAME}"

SRC_DIR="output/${VARIANT}"
QCOW2="${SRC_DIR}/${VM_NAME}.qcow2"
OUT_DIR="output/ova"
WORK="${OUT_DIR}/tmp-${VARIANT}"

mkdir -p "$OUT_DIR" "$WORK"

echo "==> Converting ${QCOW2} → VMDK (streamOptimized)..."
VMDK="${WORK}/${VM_NAME}-disk.vmdk"
qemu-img convert -p -f qcow2 -O vmdk -o subformat=streamOptimized \
    "$QCOW2" "$VMDK"

VIRTUAL_SIZE=$(qemu-img info --output=json "$VMDK" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['virtual-size'])")
DISK_CAPACITY_SECTORS=$(( VIRTUAL_SIZE / 512 ))

# Human-readable disk size for OVF description
DISK_GB=$(( (VIRTUAL_SIZE + 1073741823) / 1073741824 ))

OVF="${WORK}/${VM_NAME}.ovf"

# Determine VM parameters per variant
if [ "$VARIANT" = "full" ]; then
    VM_DESCRIPTION="All-in-one: Frigate + Mosquitto + Home Assistant. Ports: 8090 (Frigate UI), 8123 (HA), 1883 (MQTT)."
    MEM_MB=4096
    VCPUS=2
    PORTS_NOTE="8090 (Frigate), 8123 (HA), 1883 (MQTT)"
else
    VM_DESCRIPTION="Frigate + Mosquitto only. Ports: 8090 (Frigate UI), 1883 (MQTT). Requires external Home Assistant."
    MEM_MB=2048
    VCPUS=2
    PORTS_NOTE="8090 (Frigate), 1883 (MQTT)"
fi

echo "==> Writing OVF descriptor..."
cat > "$OVF" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1"
          xmlns:cim="http://schemas.dmtf.org/wbem/wscim/1/common"
          xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
          xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
          xmlns:vmw="http://www.vmware.com/schema/ovf"
          xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://schemas.dmtf.org/ovf/envelope/1 http://schemas.dmtf.org/ovf/envelope/1/dsp8023_1.1.0.xsd">

  <References>
    <File ovf:href="${VM_NAME}-disk.vmdk" ovf:id="file1"/>
  </References>

  <DiskSection>
    <Info>List of the virtual disks</Info>
    <Disk ovf:capacity="${VIRTUAL_SIZE}"
          ovf:capacityAllocationUnits="byte"
          ovf:diskId="disk1"
          ovf:fileRef="file1"
          ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"
          ovf:populatedSize="0"/>
  </DiskSection>

  <NetworkSection>
    <Info>List of logical networks</Info>
    <Network ovf:name="VM Network">
      <Description>The default VM network. Bridge to LAN so the container can reach the camera.</Description>
    </Network>
  </NetworkSection>

  <VirtualSystem ovf:id="${VM_NAME}">
    <Info>parking-empty-alert ${VARIANT} v${VERSION}</Info>
    <Name>${VM_NAME}</Name>

    <AnnotationSection>
      <Info>A human-readable annotation</Info>
      <Annotation>parking-empty-alert v${VERSION} — ${VM_DESCRIPTION}
Exposed ports: ${PORTS_NOTE}.
On first boot the wizard asks for camera IP, RTSP credentials, and WhatsApp settings.
Source: https://github.com/marczyn/parking-empty-alert</Annotation>
    </AnnotationSection>

    <OperatingSystemSection ovf:id="96" vmw:osType="debian12_64Guest">
      <Info>Operating system installed in the VM</Info>
      <Description>Debian GNU/Linux 12 (bookworm) 64-bit</Description>
    </OperatingSystemSection>

    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>${VM_NAME}</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>vmx-19</vssd:VirtualSystemType>
      </System>

      <!-- vCPUs -->
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>${VCPUS} virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>${VCPUS}</rasd:VirtualQuantity>
      </Item>

      <!-- RAM -->
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory size</rasd:Description>
        <rasd:ElementName>${MEM_MB} MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>${MEM_MB}</rasd:VirtualQuantity>
      </Item>

      <!-- SCSI controller -->
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>SCSI Controller</rasd:Description>
        <rasd:ElementName>scsiController0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>
        <rasd:ResourceType>6</rasd:ResourceType>
      </Item>

      <!-- Disk -->
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>disk0</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/disk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>

      <!-- Network adapter (VMXNET3 for best performance; e1000e for compatibility) -->
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>VM Network</rasd:Connection>
        <rasd:Description>Network adapter</rasd:Description>
        <rasd:ElementName>ethernet0</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>VirtualVmxnet3</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>

      <!-- Video -->
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>video</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceType>24</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="enable3DSupport" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="videoRamSizeInKB" vmw:value="4096"/>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
EOF

# Manifest (SHA256 checksums — required by ESXi strict import)
echo "==> Writing manifest..."
MF="${WORK}/${VM_NAME}.mf"
OVF_SHA=$(sha256sum "$OVF"  | awk '{print $1}')
VMD_SHA=$(sha256sum "$VMDK" | awk '{print $1}')
cat > "$MF" <<EOF
SHA256(${VM_NAME}.ovf)= ${OVF_SHA}
SHA256(${VM_NAME}-disk.vmdk)= ${VMD_SHA}
EOF

# Package: OVF must be first entry in the tar archive
echo "==> Packaging OVA..."
OVA="${OUT_DIR}/${VM_NAME}.ova"
(cd "$WORK" && tar cvf "../${VM_NAME}.ova" \
    "${VM_NAME}.ovf" \
    "${VM_NAME}-disk.vmdk" \
    "${VM_NAME}.mf")

rm -rf "$WORK"

OVA_SIZE=$(du -sh "$OVA" | cut -f1)
echo "==> OVA ready: ${OVA} (${OVA_SIZE})"
