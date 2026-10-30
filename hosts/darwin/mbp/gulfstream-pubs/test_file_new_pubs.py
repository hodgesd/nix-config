"""identify() against front-matter text from real pubs (trimmed).

Run: python3 -m unittest hosts/darwin/mbp/gulfstream-pubs/test_file_new_pubs.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from file_new_pubs import NeedsReview, Pub, identify  # noqa: E402

TANDC = "GVII-G500 OPERATING MANUAL ISSUE 1\nTerms and Conditions\nThese terms ... Revision 3 May 1, 2001"


class Identify(unittest.TestCase):
    def test_current_om_with_issue(self) -> None:
        pages = ["GVII-G500 OPERATING MANUAL ISSUE 1\nGVII-G500\nOperating Manual\nGVII™\nG500™\nIssue 1\n"
                 "Gulfstream Aerospace\nGAC-AC-G500-OM-0002\nRevision 21\nAugust 24, 2026", TANDC]
        kw = ('"OEM Provided Data GVII-G500 Operating Manual Issue 1  Operating Manual OM GAC-AC-G500-OM-0002 '
              'Revision 21 21 August 24, 2026 2026-08-24 GVII™ G500™ GVII- G500 "')
        self.assertEqual(identify(kw, pages), Pub("G500", "OM", "1", 21, "2026-08-24"))

    def test_afm_without_issue(self) -> None:
        pages = ["GVII-G600 AIRPLANE FLIGHT MANUAL\nGVII-G600\nAirplane Flight Manual\nGAC-AC-GVII-G600-OPS-0001",
                 "GVII-G600 AIRPLANE FLIGHT MANUAL\nThis page intentionally left blank",
                 "GVII-G600 AIRPLANE FLIGHT MANUAL\nGVII-G600\nAirplane Flight Manual\nRevision 14\nSeptember 1, 2026"]
        self.assertEqual(identify("", pages), Pub("G600", "AFM", None, 14, "2026-09-01"))

    def test_basic_issue_is_rev0(self) -> None:
        pages = ["OPERATING\nMANUAL\nDOCUMENT NUMBER\nGAC-AC-GVII-G600-OM-0001\nBASIC ISSUE\nJune 28, 2019",
                 "OPERATING MANUAL\nTo: All Gulfstream GVII-G600 Operators"]
        self.assertEqual(identify("", pages), Pub("G600", "OM", None, 0, "2019-06-28"))

    def test_date_of_issue_is_not_an_issue_number(self) -> None:
        pages = ["07/29/2019\nDATE OF ISSUE\nAIRPLANE FLIGHT MANUAL GULFSTREAM AEROSPACE\nGVII-G600\n"
                 "REVISION 1\nSEPTEMBER 25, 2019\nAIRPLANE FLIGHT MANUAL"]
        self.assertEqual(identify("", pages), Pub("G600", "AFM", None, 1, "2019-09-25"))

    def test_om_tab_index_mentioning_afm(self) -> None:
        pages = ["GVII-G500 ISSUE 1\nAOM TAB INDEX\nAIRPLANE FLIGHT MANUAL\nProduction",
                 "OPERATING\nMANUAL\nISSUE 1\nGAC-AC-GVII-G500-OM-0002\nREVISION 2\nAUGUST 18, 2020",
                 "OPERATING MANUAL\nLetter to Operators"]
        self.assertEqual(identify("", pages), Pub("G500", "OM", "1", 2, "2020-08-18"))

    def test_reissue_cover_beats_record_of_revisions(self) -> None:
        pages = ["OPERATING\nMANUAL\nDOCUMENT NUMBER\nGAC-AC-GVII-G500-OM-001\nREISSUE REV. 1\nNOVEMBER 16, 2018",
                 "OPERATING MANUAL\nRECORD OF REVISIONS\nBASIC ISSUE JULY 20, 2018\nREVISION 1 NOVEMBER 16,"]
        self.assertEqual(identify("", pages), Pub("G500", "OM", None, 1, "2018-11-16"))

    def test_missed_cover_wording_goes_to_review(self) -> None:
        pages = ["OPERATING MANUAL GVII-G500 REPRINTED AS RV 3 MAY 1, 2019",
                 "OPERATING MANUAL\nBASIC ISSUE JULY 20, 2018\nREVISION 3"]
        with self.assertRaises(NeedsReview):
            identify("", pages)

    def test_metadata_disagreeing_with_title_page(self) -> None:
        pages = ["GVII-G600 AIRPLANE FLIGHT MANUAL\nRevision 14\nSeptember 1, 2026"]
        kw = "FAA APPROVED GVII-G600 Airplane Flight Manual AFM Revision 10 10 February 13, 2025 2025-02-13"
        with self.assertRaises(NeedsReview):
            identify(kw, pages)

    def test_supplement_goes_to_review(self) -> None:
        pages = ["GVII-G500 AFMS GVII-G500 (ISSUE 1)-2020-04\nFAA APPROVED AIRPLANE FLIGHT MANUAL SUPPLEMENT FOR\n"
                 "GULFSTREAM MODEL GVII-G500\nRevision 2 April 08, 2024"]
        with self.assertRaises(NeedsReview):
            identify("", pages)

    def test_garbled_text_goes_to_review(self) -> None:
        with self.assertRaises(NeedsReview):
            identify("", ["~a~! | ,1'(; | *XOIVWUHDP$HURVSDFH | 5HYLVLRQ"])


if __name__ == "__main__":
    unittest.main()
