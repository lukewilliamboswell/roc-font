These22 original UPL fonts test font-defined NSM directionality and pass
reversal, independently of Unicode character properties. They use proper
Silf5.0 headers and32-bit class offsets; all22 pass OTS9.3 with Graphite
tables retained. The1792 ordinary cases cover native direction, automatic
script direction, requested direction, leading/trailing marks, changing a
base into a mark, and both cluster levels. Another192 cases pin the
directionality property byte conversion (16,272,-240,528 agree).

All1984 exact HB14.6/Graphite2 answers remain unmodified. The current
physical-group prototype matches1440;544 reverse-pass plus NSM cases are
still under investigation. They are not declared divergences and must not
be waived by a blanket feature policy. No activation-ready claim is made.
