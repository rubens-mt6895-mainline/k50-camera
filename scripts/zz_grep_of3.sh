#!/bin/bash
K=${KDIR}
echo "--- struct of_changeset definition ---"
grep -rn "struct of_changeset {" $K/include/ $K/drivers/of/ 2>/dev/null
echo "--- of_changeset prototypes in include/ ---"
grep -rn "of_changeset_init\|of_changeset_create_node\|of_changeset_add_prop_u32_array\|of_changeset_apply\|of_changeset_revert\|of_changeset_destroy\|of_changeset_action" $K/include/ 2>/dev/null
echo "--- where is of_changeset declared (all) ---"
grep -rln "struct of_changeset" $K/include/ 2>/dev/null
echo "--- of_platform_notify ---"
sed -n '720,790p' $K/drivers/of/platform.c
echo "--- of_iommu_xlate ---"
sed -n '1,45p' $K/drivers/iommu/of_iommu.c
echo "--- MTK_M4U macros ---"
grep -rn "define MTK_M4U_TO_DOM\|define MTK_M4U_TO_LARB\|define MTK_M4U_TO_PORT\|define MTK_M4U_TO_TAB\|define MTK_M4U_TO_BANK\|define MTK_M4U_ID" $K/drivers/iommu/ $K/include/ 2>/dev/null
