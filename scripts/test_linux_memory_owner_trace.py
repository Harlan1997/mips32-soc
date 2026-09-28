#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

from check_linux_memory_owner_trace import validate


GOOD = """\
LINUX_MEMORY_OWNER_L2 cycle=10 line=08c4ea80 state=0 s_ar=0/1/00000000 s_r=0/0/00000000/0 m_ar=1/1/08c4ea80 m_r=0/0/00000000/0
LINUX_MEMORY_OWNER_L2_ARRAY cycle=10 line=08c4ea80 valid=0 tag=00000000 words=00000000/00000000/00000000/00000000/00000000/00000000/00000000/00000000
LINUX_MEMORY_OWNER_DDR cycle=10 line=08c4ea80 backend=ddr_controller word_index=15008 s_ar=1/1/08c4ea80 s_r=0/0/00000000/0 words=00000000/00000000/00000000/00000000/00000000/00000000/00000000/00000000
LINUX_MEMORY_OWNER_STORE cycle=10 line=08c4ea80 cpu_req=0 we=0 addr=08c4ea9c data=00000000 be=0 addr_ok=0
"""


class MemoryOwnerTraceTest(unittest.TestCase):
    def write(self, text: str) -> Path:
        handle = tempfile.NamedTemporaryFile(mode="w", delete=False)
        handle.write(text)
        handle.close()
        return Path(handle.name)

    def test_valid_groups(self) -> None:
        path = self.write(GOOD)
        self.assertEqual(validate(path), (4, 1))

    def test_rejects_nil(self) -> None:
        path = self.write(GOOD.replace("words=00000000", "words=<NIL>", 1))
        with self.assertRaises(ValueError):
            validate(path)

    def test_rejects_missing_group(self) -> None:
        path = self.write("\n".join(GOOD.splitlines()[:2]) + "\n")
        with self.assertRaises(ValueError):
            validate(path)


if __name__ == "__main__":
    unittest.main()
