-- The game's sounds for melee hits on characters (SoundCues). The game plays them at 15-50 % volume (and the
-- body hit at pitch 0.8), so hits sound weak; hitSoundVolume in config.lua sets them all to one volume.
-- The armor sounds are picked by the target's armor and the weapon (CombatModule_AI_Humanoid SoundArmorBlunt /
-- SoundArmorSharp), the body hit and the stab by the weapon.
local D = "/Game/Audio_Grayshaft/01_GS_Audio/FX/Combat/"
local function cue(dir, name) return D .. dir .. "/" .. name .. "." .. name end
return {
    cue("Damage_To_Enemies/Lives/People/Unprotected/Cutting_Weapons", "a_gs_Unprotected_CuttingW_FM"),
    cue("Damage_To_Enemies/Lives/People/Unprotected/Crushing_Weapons", "a_gs_Unprotected_CrushingW_FM"),
    cue("Damage_To_Enemies/Lives/People/Leather_Armor/Cutting_Weapons", "a_gs_Leather_Armor_CuttingW_FM"),
    cue("Damage_To_Enemies/Lives/People/Leather_Armor/Crushing_Weapons", "a_gs_Leather_Armor_CrushingW_FM"),
    cue("Damage_To_Enemies/Lives/People/Iron_Armor/Cutting_Weapons", "a_gs_Iron_Armor_CuttingW_FM"),
    cue("Damage_To_Enemies/Lives/People/Iron_Armor/Crushing_Weapons", "a_gs_Iron_Armor_CrushingW_FM"),
    cue("Damage_To_Enemies/Lives/People/Medium_Armor", "ArmedHit"),
    cue("Damage_To_Enemies/Not_Lives/Bone/Cutting_Weapons", "a_gs_Bone_CuttingW_FM"),
    cue("Damage_To_Enemies/Not_Lives/Bone/Crushing_Weapons", "a_gs_Bone_CrushingW_FM"),
    cue("Arms/Sword_Hit_Body", "a_gs_Sword_Hit_body_final_mix"),
    cue("Arms/Knife_Stab", "a_gs_Knife_Stab_final_mix"),
}
