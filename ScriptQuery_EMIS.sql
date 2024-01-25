/*--------Part1----------*/

USE [EMIS];
CREATE TABLE #temp_PostCode (
    [postcode] [nvarchar](50),
    [total_patient_count] [int]
);

WITH PostcodePatientCounts AS (
    SELECT 
        [postcode],
        COUNT(*) as [total_patient_count],
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS [rn]
    FROM 
        [dbo].[patient]
    Where [postcode] IS NOT NULL
    GROUP BY 
        [postcode]
)
INSERT INTO #temp_PostCode ([postcode], [total_patient_count])
SELECT 
    [postcode],
    [total_patient_count]
FROM 
    PostcodePatientCounts
WHERE 
    [rn] <= 2;

/*--------Part2----------*/

USE [EMIS];

WITH EligiblePatients AS (
    SELECT 
        p.[patient_id], 
        p.[patient_givenname] + ' ' + p.[patient_surname] AS [full_name],
        p.[postcode],
        p.[age],
        p.[gender],
        p.[registration_guid], 
        p.[date_of_birth]
    FROM 
        [dbo].[patient] p
    WHERE 
        p.[postcode] IN (  SELECT [postcode] FROM #temp_PostCode )
	  /*p.[postcode] IN ( SELECT TOP 2 [postcode]
                          FROM [dbo].[patient]
                          GROUP BY [postcode]
                          ORDER BY COUNT(*) DESC
                        )
	  */
        AND p.[registration_guid] IN (
            SELECT [registration_guid]
            FROM [dbo].[clinical_codes] CC
			JOIN [dbo].[observation] OB ON  CC.[snomed_concept_id] = OB.[snomed_concept_id]
            WHERE CC.[refset_simple_id] = 999012891000230104 -- Asthma refset
            AND OB.[end_date] IS NULL -- Not resolved
			AND p.[registration_guid] = OB.[registration_guid]
        )
        AND p.[registration_guid] NOT IN (
            SELECT [registration_guid]
            FROM [dbo].[clinical_codes] CC
			JOIN [dbo].[observation] OB ON  CC.[snomed_concept_id] = OB.[snomed_concept_id]
            WHERE [refset_simple_id] = 999004211000230104 -- Smoker refset
			AND p.[registration_guid] = OB.[registration_guid]
        )
        AND p.[registration_guid] NOT IN (
            SELECT [registration_guid]
            FROM [dbo].[observation] OB
            WHERE [snomed_concept_id] = 27113001 -- Weight less than 40kg
			AND p.[registration_guid] = OB.[registration_guid]
        )
        AND p.[registration_guid] NOT IN (
            SELECT [registration_guid]
            FROM [dbo].[clinical_codes] CC
			INNER JOIN [dbo].[observation] OB ON  CC.[snomed_concept_id] = OB.[snomed_concept_id]
            WHERE [refset_simple_id] = 999011571000230107 -- COPD refset
            AND OB.[end_date] IS NULL -- Not resolved
			AND p.[registration_guid] = OB.[registration_guid]
        )
)
SELECT 
    ep.*,
    m.[emis_original_term] AS [medication_name],
    o.[emis_original_term] AS [observation_name]
FROM 
    EligiblePatients ep
JOIN 
    [dbo].[medication] m ON ep.[registration_guid] = m.[registration_guid]
JOIN 
    [dbo].[observation] o ON ep.[registration_guid] = o.[registration_guid]
JOIN 
    [dbo].[clinical_codes] c ON m.[snomed_concept_id] = c.[snomed_concept_id]
WHERE 
    (---Check For Prescribed Medication
      (m.[snomed_concept_id] =129490002 and (c.[code_id] = 591221000033116  OR c.[parent_code_id] = 591221000033116)) ---Formoterol Fumarate
	OR(m.[snomed_concept_id] =108606009 and (c.[code_id] = 717321000033118  OR c.[parent_code_id] = 717321000033118))  ---Salmeterol Xinafoate
	OR(m.[snomed_concept_id] =702408004 and (c.[code_id] = 1215621000033114 OR c.[parent_code_id] = 1215621000033114)) ---Vilanterol 
	OR(m.[snomed_concept_id] =702801003 and (c.[code_id] = 972021000033115  OR c.[parent_code_id] = 972021000033115))  ---Indacaterol 
	OR(m.[snomed_concept_id] =704459002 and (c.[code_id] = 1223821000033118 OR c.[parent_code_id] = 1223821000033118)) ---Olodaterol  
	 )
    AND m.[recorded_date] >= DATEADD(year, -30, GETDATE()) --- in the Last 30 years
    AND o.[observation_type] <> 'type 1 opt out' 
    AND o.[observation_type] <> 'connected care opt out'
