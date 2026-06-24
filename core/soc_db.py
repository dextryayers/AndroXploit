#!/usr/bin/env python3
import re

class SoCDatabase:
    MEDIATEK = {
        "mt6761": "Helio A22",
        "mt6762": "Helio P22",
        "mt6763": "Helio P23",
        "mt6765": "Helio G25/P35",
        "mt6768": "Helio G70/G80/G85",
        "mt6771": "Helio P60/P70",
        "mt6779": "Helio P90",
        "mt6785": "Helio G90/G90T",
        "mt6781": "Helio G96",
        "mt6789": "Helio G99",
        "mt6833": "Dimensity 700",
        "mt6835": "Dimensity 6100+",
        "mt6853": "Dimensity 720",
        "mt6855": "Dimensity 6300/6300+",
        "mt6873": "Dimensity 800",
        "mt6875": "Dimensity 820",
        "mt6877": "Dimensity 900",
        "mt6878": "Dimensity 7200",
        "mt6879": "Dimensity 8200",
        "mt6883": "Dimensity 1000",
        "mt6885": "Dimensity 1000+",
        "mt6886": "Dimensity 1000C",
        "mt6889": "Dimensity 1200",
        "mt6891": "Dimensity 1100",
        "mt6893": "Dimensity 1200",
        "mt6895": "Dimensity 8100/8200",
        "mt6975": "Dimensity 9000+",
        "mt6983": "Dimensity 9000",
        "mt6985": "Dimensity 9200",
        "mt6989": "Dimensity 9300",
        "mt6990": "Dimensity 9400",
        "mt8673": "Dimensity 1000 TV",
        "mt8771": "Pentonic 700",
        "mt8773": "Pentonic 1000",
    }

    MEDIATEK_G = {
        "mt6765": "Helio G35",
        "mt6768": "Helio G70/G80",
        "mt6771": "Helio G90 series",
        "mt6785": "Helio G90/G90T",
        "mt6781": "Helio G96",
        "mt6789": "Helio G99 Ultra",
        "mt6833": "Dimensity 700 (G-class)",
    }

    QUALCOMM = {
        "msm8916": "Snapdragon 410",
        "msm8939": "Snapdragon 615",
        "msm8952": "Snapdragon 617",
        "msm8953": "Snapdragon 625",
        "msm8956": "Snapdragon 650",
        "msm8976": "Snapdragon 652/653",
        "msm8992": "Snapdragon 808",
        "msm8994": "Snapdragon 810",
        "msm8996": "Snapdragon 820/821",
        "msm8998": "Snapdragon 835",
        "sdm439": "Snapdragon 439",
        "sdm450": "Snapdragon 450",
        "sdm632": "Snapdragon 632",
        "sdm636": "Snapdragon 636",
        "sdm660": "Snapdragon 660",
        "sdm670": "Snapdragon 670",
        "sdm710": "Snapdragon 710",
        "sdm712": "Snapdragon 712",
        "sdm730": "Snapdragon 730/730G",
        "sdm732": "Snapdragon 732G",
        "sdm765": "Snapdragon 765/765G",
        "sdm768": "Snapdragon 768G",
        "sdm835": "Snapdragon 835",
        "sdm845": "Snapdragon 845",
        "sdm855": "Snapdragon 855/855+",
        "sdm860": "Snapdragon 860",
        "sdm865": "Snapdragon 865/865+",
        "sdm870": "Snapdragon 870",
        "sm7225": "Snapdragon 750G",
        "sm7250": "Snapdragon 765/765G",
        "sm7255": "Snapdragon 768G",
        "sm7325": "Snapdragon 778G",
        "sm7350": "Snapdragon 780G",
        "sm7355": "Snapdragon 782G",
        "sm7425": "Snapdragon 790",
        "sm7450": "Snapdragon 8 Gen 1",
        "sm7455": "Snapdragon 8+ Gen 1",
        "sm7460": "Snapdragon 7 Gen 1",
        "sm7475": "Snapdragon 7+ Gen 2",
        "sm8350": "Snapdragon 888",
        "sm8355": "Snapdragon 888+",
        "sm8450": "Snapdragon 8 Gen 1",
        "sm8475": "Snapdragon 8+ Gen 1",
        "sm8525": "Snapdragon 8cx Gen 3",
        "sm8550": "Snapdragon 8 Gen 2",
        "sm8560": "Snapdragon 8 Gen 2 (+OC)",
        "sm8635": "Snapdragon 7+ Gen 3",
        "sm8650": "Snapdragon 8 Gen 3",
        "sm8750": "Snapdragon 8 Gen 4",
        "sm8550": "Snapdragon 8 Gen 2",
    }

    UNISOC = {
        "sc9832": "Spreadtrum SC9832",
        "sc9850": "Spreadtrum SC9850",
        "sc9863": "Unisoc SC9863",
        "t606": "Unisoc T606",
        "t608": "Unisoc T608",
        "t610": "Unisoc T610",
        "t612": "Unisoc T612",
        "t614": "Unisoc T614",
        "t616": "Unisoc T616",
        "t618": "Unisoc T618",
        "t619": "Unisoc T619",
        "t620": "Unisoc T620",
        "t700": "Unisoc T700",
        "t710": "Unisoc T710",
        "t720": "Unisoc T720",
        "t740": "Unisoc T740",
        "t750": "Unisoc T750",
        "t760": "Unisoc T760",
        "t765": "Unisoc T765",
        "t770": "Unisoc T770",
        "t820": "Unisoc T820",
    }

    SAMSUNG = {
        "exynos": "Exynos",
        "exynos7": "Exynos 7",
        "exynos8": "Exynos 8",
        "exynos9": "Exynos 9",
        "exynos9610": "Exynos 9610",
        "exynos9611": "Exynos 9611",
        "exynos9810": "Exynos 9810",
        "exynos9820": "Exynos 9820",
        "exynos9825": "Exynos 9825",
        "exynos990": "Exynos 990",
        "exynos1080": "Exynos 1080",
        "exynos2100": "Exynos 2100",
        "exynos2200": "Exynos 2200",
        "exynos2400": "Exynos 2400",
        "exynos2500": "Exynos 2500",
    }

    HUAWEI = {
        "kirin": "HiSilicon Kirin",
        "kirin620": "Kirin 620",
        "kirin650": "Kirin 650",
        "kirin655": "Kirin 655",
        "kirin658": "Kirin 658",
        "kirin659": "Kirin 659",
        "kirin710": "Kirin 710",
        "kirin8000": "Kirin 8000",
        "kirin810": "Kirin 810",
        "kirin820": "Kirin 820",
        "kirin9000": "Kirin 9000",
        "kirin9000s": "Kirin 9000S",
        "kirin9010": "Kirin 9010",
    }

    ROCKCHIP = {
        "rk2928": "RK2928",
        "rk3026": "RK3026",
        "rk3036": "RK3036",
        "rk3066": "RK3066",
        "rk3128": "RK3128",
        "rk3188": "RK3188",
        "rk3229": "RK3229",
        "rk3288": "RK3288",
        "rk3328": "RK3328",
        "rk3368": "RK3368",
        "rk3399": "RK3399",
        "rk3566": "RK3566",
        "rk3568": "RK3568",
        "rk3588": "RK3588",
    }

    def _normalize_platform(self, platform):
        return platform.lower().replace("-", "").replace("_", "").replace(" ", "")

    def detect_soc(self, props, cpu_impl=None, cpu_part=None):
        platform = props.get("ro.board.platform", "")
        hardware = props.get("ro.hardware", "")
        chipname = props.get("ro.chipname", "").lower()
        soc = self._normalize_platform(platform)

        result = {"vendor": "Unknown", "series": "Unknown", "model": "Unknown", "full_name": "Unknown SoC"}

        if not soc and not chipname and cpu_impl:
            return self._detect_from_impl(cpu_impl, cpu_part)

        if not soc and chipname:
            soc = self._normalize_platform(chipname)

        if not soc:
            soc = self._normalize_platform(hardware)

        result["platform_raw"] = platform

        for prefix, series_name in [("mt", "MediaTek"), ("sm", "Qualcomm Snapdragon"),
                                     ("msm", "Qualcomm Snapdragon"), ("sdm", "Qualcomm Snapdragon"),
                                     ("sc", "Unisoc/Spreadtrum"), ("t", "Unisoc"),
                                     ("exynos", "Samsung Exynos"),
                                     ("kirin", "HiSilicon Kirin"), ("rk", "Rockchip")]:
            if soc.startswith(prefix):
                result["vendor"] = series_name.split()[0]
                if "Qualcomm" in series_name:
                    result["vendor"] = "Qualcomm"
                elif "Samsung" in series_name:
                    result["vendor"] = "Samsung"
                break

        all_chips = {}
        all_chips.update(self.MEDIATEK)
        all_chips.update(self.QUALCOMM)
        all_chips.update(self.UNISOC)
        all_chips.update(self.SAMSUNG)
        all_chips.update(self.HUAWEI)
        all_chips.update(self.ROCKCHIP)

        best_match = None
        best_len = 0
        for chip_id, model_name in all_chips.items():
            nid = self._normalize_platform(chip_id)
            if soc.startswith(nid) and len(nid) > best_len:
                best_match = model_name
                best_len = len(nid)
            elif chipname.startswith(nid) and len(nid) > best_len:
                best_match = model_name
                best_len = len(nid)

        if best_match:
            result["model"] = best_match
            for vendor_key in [("MediaTek", "MediaTek"), ("Qualcomm", "Qualcomm"),
                                ("Unisoc", "Unisoc"), ("Samsung", "Samsung"),
                                ("HiSilicon", "HiSilicon"), ("Rockchip", "Rockchip")]:
                vname = vendor_key[0]
                if vname in best_match:
                    result["vendor"] = vname
                    break
            result["full_name"] = best_match
            if "MediaTek" in best_match:
                result["series"] = "Helio" if "helio" in best_match.lower() else "Dimensity"
            elif "Snapdragon" in best_match:
                result["series"] = "Snapdragon"
            elif "Exynos" in best_match:
                result["series"] = "Exynos"
            elif "Kirin" in best_match:
                result["series"] = "Kirin"
            elif "Unisoc" in best_match or "Spreadtrum" in best_match:
                result["series"] = "Unisoc"
            elif "RK" in best_match:
                result["series"] = "Rockchip"
        else:
            for prefix, vendor_name, series_name in [
                ("mt", "MediaTek", "MediaTek"),
                ("sm", "Qualcomm", "Snapdragon"),
                ("msm", "Qualcomm", "Snapdragon"),
                ("sdm", "Qualcomm", "Snapdragon"),
                ("sc", "Unisoc", "Unisoc"),
                ("exynos", "Samsung", "Exynos"),
                ("kirin", "HiSilicon", "Kirin"),
                ("rk", "Rockchip", "Rockchip"),
            ]:
                if soc.startswith(prefix):
                    result["vendor"] = vendor_name
                    result["series"] = series_name
                    result["model"] = platform
                    if vendor_name == "MediaTek":
                        if any(g in soc for g in ["6765", "6768", "6781", "6785", "6789"]):
                            result["series"] = "Helio G"
                        elif any(d in soc for d in ["6833", "6853", "6873", "6877", "6883", "6885", "6889", "6891", "6893", "6895", "6975", "6983", "6985", "6989", "6990"]):
                            result["series"] = "Dimensity"
                        else:
                            result["series"] = "Helio"
                        result["full_name"] = f"MediaTek {result['series']} ({platform})"
                    elif vendor_name == "Qualcomm":
                        result["full_name"] = f"Qualcomm Snapdragon ({platform})"
                    elif vendor_name == "Samsung":
                        result["full_name"] = f"Samsung {series_name} ({platform})"
                    elif vendor_name == "HiSilicon":
                        result["full_name"] = f"HiSilicon {series_name} ({platform})"
                    elif vendor_name == "Unisoc":
                        result["full_name"] = f"Unisoc ({platform})"
                    else:
                        result["full_name"] = f"{vendor_name} {series_name} ({platform})"
                    break

        if result["full_name"] == "Unknown SoC":
            result["full_name"] = f"{result['vendor']} {result['series']} ({platform})" if platform else "Unknown SoC"

        if cpu_impl:
            impl_name = {
                "0x41": "ARM", "0x42": "Broadcom", "0x43": "Cavium", "0x44": "DEC",
                "0x46": "Fujitsu", "0x48": "HiSilicon", "0x49": "Infineon",
                "0x4d": "Motorola", "0x4e": "NEC", "0x50": "Qualcomm", "0x51": "Qualcomm",
                "0x53": "Samsung", "0x54": "TI", "0x55": "Marvell", "0x56": "Marvell",
                "0x61": "Apple", "0x66": "Faraday", "0x68": "MediaTek", "0x69": "MediaTek",
                "0x70": "Nvidia", "0x72": "Rockchip", "0x73": "Rockchip",
                "0x78": "Unisoc", "0xc0": "Ampere",
            }.get(cpu_impl, "Unknown")
            if result["vendor"] == "Unknown":
                result["vendor"] = impl_name
            result["cpu_impl_name"] = impl_name

        return result

    def _detect_from_impl(self, impl, part):
        vendor_map = {
            "0x41": "ARM", "0x50": "Qualcomm", "0x51": "Qualcomm",
            "0x68": "MediaTek", "0x69": "MediaTek",
            "0x53": "Samsung", "0x48": "HiSilicon",
            "0x78": "Unisoc", "0x72": "Rockchip", "0x73": "Rockchip",
        }
        vendor = vendor_map.get(impl, "Unknown")
        return {
            "vendor": vendor,
            "series": "ARM Cortex" if impl == "0x41" else vendor,
            "model": f"Part 0x{part}" if part else "Unknown",
            "full_name": f"{vendor} (CPU implementer 0x{impl.replace('0x','')})" if impl else "Unknown SoC",
            "cpu_impl_name": vendor,
        }


def detect_cpu(props, cpu_impl=None, cpu_part=None):
    db = SoCDatabase()
    return db.detect_soc(props, cpu_impl, cpu_part)


def get_cpu_full_name(props, cpu_impl=None, cpu_part=None):
    result = detect_cpu(props, cpu_impl, cpu_part)
    return result["full_name"]
