-- Set indicator_labels for existing "Change Baby" predefined chores
UPDATE chores
SET indicator_labels = '["💩 poo","💛 pee"]'
WHERE name = 'Change Baby'
  AND is_predefined = TRUE
  AND indicator_labels = '[]';
