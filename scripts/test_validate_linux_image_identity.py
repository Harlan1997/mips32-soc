#!/usr/bin/env python3
import hashlib
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import validate_linux_image_identity as identity


class ImageIdentityTest(unittest.TestCase):
    def test_matching_bundle_and_override_pass(self):
        with tempfile.TemporaryDirectory() as root:
            image = Path(root) / "image"
            image.mkdir()
            kernel = Path(root) / "vmlinux"
            kernel.write_bytes(b"kernel")
            (image / "mips32_soc_ref_rtl.dtb").write_bytes(b"dtb")
            (image / "bootrom.hex").write_bytes(b"bootrom")
            (image / "ddr.hex").write_bytes(b"ddr")

            def digest(name):
                return hashlib.sha256((image / name).read_bytes()).hexdigest()

            (image / "image_manifest.txt").write_text(
                "\n".join([
                    f"KERNEL={kernel}",
                    f"KERNEL_SHA256={hashlib.sha256(b'kernel').hexdigest()}",
                    "DTB=mips32_soc_ref_rtl.dtb",
                    f"DTB_SHA256={digest('mips32_soc_ref_rtl.dtb')}",
                    f"BOOTROM_SHA256={digest('bootrom.hex')}",
                    f"DDR_SHA256={digest('ddr.hex')}",
                ]) + "\n",
                encoding="utf-8",
            )
            result = identity.validate(image, kernel, image / "mips32_soc_ref_rtl.dtb")
            self.assertEqual(result["dtb_sha256"], digest("mips32_soc_ref_rtl.dtb"))

    def test_wrong_dtb_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            image = Path(root) / "image"
            image.mkdir()
            kernel = Path(root) / "vmlinux"
            kernel.write_bytes(b"kernel")
            dtb = image / "mips32_soc_ref_rtl.dtb"
            dtb.write_bytes(b"dtb")
            (image / "bootrom.hex").write_bytes(b"bootrom")
            (image / "ddr.hex").write_bytes(b"ddr")

            def digest(path):
                return hashlib.sha256(path.read_bytes()).hexdigest()

            (image / "image_manifest.txt").write_text(
                f"KERNEL={kernel}\n"
                f"KERNEL_SHA256={digest(kernel)}\n"
                "DTB=mips32_soc_ref_rtl.dtb\n"
                f"DTB_SHA256={digest(dtb)}\n"
                f"BOOTROM_SHA256={digest(image / 'bootrom.hex')}\n"
                f"DDR_SHA256={digest(image / 'ddr.hex')}\n",
                encoding="utf-8",
            )
            wrong = Path(root) / "wrong.dtb"
            wrong.write_bytes(b"different-dtb")
            with self.assertRaisesRegex(ValueError, "DTB override mismatch"):
                identity.validate(image, kernel, wrong)


if __name__ == "__main__":
    unittest.main()
