dnj = {}

dnj.maxsalary = 20000

dnj.jobs = {
    ['police'] = {
        label = 'Policie',
        boss_grades = { 4, 5 },
        salary_from_void = true, -- true = peniaze z vyplaty pojdu z voidu nie z kasy , false = vyplaty pojdu z kasy , takze ked je v kase napr. 10k$ a hrac ma vyplatu 5k$ tak vyplatu dostane a z kasy to odpocita 5k
        coords = vector3(454.6316, -993.1389, 30.6896),
        target_label = 'Boss Menu Policie',
    },
}

dnj.salaryinterval = 30