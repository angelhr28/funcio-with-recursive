SET client_min_messages = notice;
DO $$
DECLARE
    ----PARAMETROS
    __YEAR     INTEGER   DEFAULT 2020;
    __PROGRAMA INTEGER   DEFAULT 2;
    __SEDE     INTEGER[] DEFAULT ARRAY[1];
    ----VARIABLES
    __MSJ           INTEGER;
    __REC_MATRIZ    RECORD;
    __JSON_MATRICES JSONB;
    __JSON_ESTRUCT  JSONB;
    __ARRAY_ORIGIN  INTEGER[];
    __ARRAY_HIJO    INTEGER[];
    __IS_ERROR      BOOLEAN;
BEGIN
    SELECT JSONB_AGG(
               JSONB_BUILD_OBJECT(
                   'nid_aula'   , a.nid_aula,
                   'estructura' , notas.__calificaciones_build_new_structure___23(pmpf.estructura, 1),
                   'id_periodo' , pmpf._id_periodo   
               )
            ORDER BY a.nid_aula, pmpf._id_periodo
           )
      INTO __JSON_MATRICES    
      FROM aula AS a,
           prog.matriz_ppff AS pmpf,
           JSONB_ARRAY_ELEMENTS(a.json_update_matriz_ppff) AS up
     WHERE pmpf._year_acad = a.year
       AND pmpf._id_sede = a.nid_sede
       AND pmpf._id_tipo_programa = a.tipo_ciclo
       AND a.nid_grado       = ANY(pmpf.id_grados);
       
    FOR __REC_MATRIZ IN SELECT nnpf._id_aula                      AS nid_aula,
                               nnpf._id_estudiante                AS id_est,
                               matriz->'estructura'               AS estructura,
                               (matriz->>'id_periodo')::INTEGER   AS id_periodo   
                          FROM notas.notas_ppff AS nnpf,
                               JSONB_ARRAY_ELEMENTS(nnpf.json_notas) AS matriz,
                               JSONB_ARRAY_ELEMENTS(__JSON_MATRICES) AS estruct
                         WHERE nnpf._id_aula = (estruct->>'nid_aula')::INTEGER
                         GROUP BY nnpf._id_aula, nnpf._id_estudiante, (matriz->>'id_periodo')::INTEGER,matriz.value 
                         ORDER BY nnpf._id_aula, matriz->>'id_periodo'
    LOOP
        -- MATRIZ DEL PAPA
        SELECT estruct->'estructura'
          INTO __JSON_ESTRUCT
          FROM JSONB_ARRAY_ELEMENTS(__JSON_MATRICES) AS estruct
         WHERE (estruct->>'nid_aula')::INTEGER    = __REC_MATRIZ.nid_aula
           AND (estruct->>'id_periodo')::INTEGER = __REC_MATRIZ.id_periodo;
    
        WITH RECURSIVE reports (json_element) AS (
            SELECT item::JSONB
             FROM JSONB_ARRAY_ELEMENTS(CASE WHEN __JSON_ESTRUCT = 'null' THEN NULL::JSONB 
                                            ELSE __JSON_ESTRUCT END) AS item
            UNION
            SELECT item
              FROM reports, JSONB_ARRAY_ELEMENTS( CASE WHEN json_element->'items' = 'null' THEN NULL::JSONB
                                                       ELSE json_element->'items' END) AS item
        )
        
        SELECT ARRAY_AGG((r.json_element->>'id')::INTEGER)
          INTO __ARRAY_ORIGIN 
          FROM reports AS r
         WHERE r.json_element->>'id' <> '0';
          
        -- MATRIZ DEL HIJO
        WITH RECURSIVE reports2 (json_element2) AS (
            SELECT item
             FROM JSONB_ARRAY_ELEMENTS(CASE WHEN __REC_MATRIZ.estructura = 'null' THEN NULL::JSONB 
                                            ELSE __REC_MATRIZ.estructura END) AS item
            UNION
            SELECT item
              FROM reports2, JSONB_ARRAY_ELEMENTS( CASE WHEN json_element2->'items' = 'null' THEN NULL::JSONB
                                                        ELSE json_element2->'items' END) AS item
        )
        SELECT ARRAY_AGG((r.json_element2->>'id')::INTEGER)
          INTO __ARRAY_HIJO 
          FROM reports2 AS r
         WHERE r.json_element2->>'id' <> '0';
          
        __ARRAY_ORIGIN := COALESCE (__ARRAY_ORIGIN, '{}'::INTEGER[]);
        __ARRAY_HIJO   := COALESCE (__ARRAY_HIJO,   '{}'::INTEGER[]);
        
        SELECT __ARRAY_ORIGIN <> __ARRAY_HIJO INTO __IS_ERROR;
        IF __IS_ERROR = TRUE THEN
            RAISE NOTICE 'ID_AULA: %    ----    ID_ALUMNO: % - %    ----    ID_PERIODO: %    ', __REC_MATRIZ.nid_aula, __REC_MATRIZ.id_est, (SELECT __nombre_corto(__REC_MATRIZ.id_est, '1') ), __REC_MATRIZ.id_periodo;
        END IF;
        
    END LOOP;
END
$$;