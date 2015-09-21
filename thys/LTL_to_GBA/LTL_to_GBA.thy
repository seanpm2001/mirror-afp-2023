section {* LTL to GBA translation *}
(*
  Author: Alexander Schimpf
    Modified by Peter Lammich

**)
theory LTL_to_GBA
imports 
  "../CAVA_Automata/CAVA_Base/CAVA_Base"
  LTL LTL_Rewrite
  "../CAVA_Automata/Automata"
begin

subsection {* Statistics *}
code_printing
  code_module Gerth_Statistics \<rightharpoonup> (SML) {*
    structure Gerth_Statistics = struct
      val active = Unsynchronized.ref false
      val data = Unsynchronized.ref (0,0,0)
 
      fun is_active () = !active
      fun set_data num_states num_init num_acc = (
        active := true; 
        data := (num_states, num_init, num_acc)
      )

      fun to_string () = let
        val (num_states, num_init, num_acc) = !data
      in
          "Num states: " ^ IntInf.toString (num_states) ^ "\n"
        ^ "  Num initial: " ^ IntInf.toString num_init ^ "\n"
        ^ "  Num acc-classes: " ^ IntInf.toString num_acc ^ "\n"
      end
        
      val _ = Statistics.register_stat ("Gerth LTL_to_GBA",is_active,to_string)
    end
*}
code_reserved SML Gerth_Statistics

consts 
  stat_set_data_int :: "integer \<Rightarrow> integer \<Rightarrow> integer \<Rightarrow> unit"

code_printing
  constant stat_set_data_int \<rightharpoonup> (SML) "Gerth'_Statistics.set'_data"

definition "stat_set_data ns ni na 
  \<equiv> stat_set_data_int (integer_of_nat ns) (integer_of_nat ni) (integer_of_nat na)"

lemma [autoref_rules]: 
  "(stat_set_data,stat_set_data) \<in> nat_rel \<rightarrow> nat_rel \<rightarrow> nat_rel \<rightarrow> unit_rel"
  by auto

abbreviation "stat_set_data_nres ns ni na \<equiv> RETURN (stat_set_data ns ni na)"

lemma discard_stat_refine[refine]:
  "m1\<le>m2 \<Longrightarrow> stat_set_data_nres ns ni na \<guillemotright> m1 \<le> m2" by simp_all

subsection {* Preliminaries *}
text {* Some very special lemmas for reasoning about the nres-monad *}
lemma SPEC_rule_nested2: 
  "\<lbrakk>m \<le> SPEC P; \<And>r1 r2. P (r1, r2) \<Longrightarrow> g (r1, r2) \<le> SPEC P\<rbrakk> 
  \<Longrightarrow> m \<le> SPEC (\<lambda>r'. g r' \<le> SPEC P)"
  by (simp add: pw_le_iff refine_pw_simps) blast

lemma SPEC_rule_param2:
  assumes "f x \<le> SPEC (P x)"
      and "\<And>r1 r2. (P x) (r1, r2) \<Longrightarrow> (P x') (r1, r2)"
    shows "f x \<le> SPEC (P x')"
  using assms 
  by (simp add: pw_le_iff refine_pw_simps)

lemma SPEC_rule_weak:
  assumes "f x \<le> SPEC (Q x)" and "f x \<le> SPEC (P x)"
      and "\<And>r1 r2. \<lbrakk>(Q x) (r1, r2); (P x) (r1, r2)\<rbrakk> \<Longrightarrow> (P x') (r1, r2)"
    shows "f x \<le> SPEC (P x')"
  using assms 
  by (simp add: pw_le_iff refine_pw_simps)

lemma SPEC_rule_weak_nested2: "\<lbrakk>f \<le> SPEC Q; f \<le> SPEC P;
  \<And>r1 r2. \<lbrakk>Q (r1, r2); P (r1, r2)\<rbrakk> \<Longrightarrow> g (r1, r2) \<le> SPEC P\<rbrakk>
  \<Longrightarrow> f \<le> SPEC (\<lambda>r'. g r' \<le> SPEC P)"
  by (simp add: pw_le_iff refine_pw_simps) blast


subsection {* Creation of States *}
text {*
  In this section, the first part of the algorithm, which creates the states of the
  automaton, is formalized.
*}

(* FIXME: Abstraktion über node_name *)

type_synonym node_name = nat

type_synonym
  'a frml = "'a ltln"

type_synonym
  'a interprt = "'a set word"

record 'a node =
  name   :: node_name
  incoming :: "node_name set"
  new :: "'a frml set"
  old :: "'a frml set"
  "next" :: "'a frml set"

context begin interpretation LTL_Syntax .

fun frml_neg
where 
  "frml_neg true\<^sub>n = false\<^sub>n"
| "frml_neg false\<^sub>n = true\<^sub>n"
| "frml_neg prop\<^sub>n(q) = nprop\<^sub>n(q)"
| "frml_neg nprop\<^sub>n(q) = prop\<^sub>n(q)"

fun new1 where
  "new1 (\<mu> and\<^sub>n \<psi>) = {\<mu>,\<psi>}"
| "new1 (\<mu> U\<^sub>n \<psi>) = {\<mu>}"
| "new1 (\<mu> V\<^sub>n \<psi>) = {\<psi>}"
| "new1 (\<mu> or\<^sub>n \<psi>) = {\<mu>}"
| "new1 _ = {}"

fun next1 where
  "next1 (X\<^sub>n \<psi>) = {\<psi>}"
| "next1 (\<mu> U\<^sub>n \<psi>) = {\<mu> U\<^sub>n \<psi>}"
| "next1 (\<mu> V\<^sub>n \<psi>) = {\<mu> V\<^sub>n \<psi>}"
| "next1 _ = {}"

fun new2 where
  "new2 (\<mu> U\<^sub>n \<psi>) = {\<psi>}"
| "new2 (\<mu> V\<^sub>n \<psi>) = {\<mu>, \<psi>}"
| "new2 (\<mu> or\<^sub>n \<psi>) = {\<psi>}"
| "new2 _ = {}"


(* FIXME: Abstraction over concrete definition *)

definition "expand_init \<equiv> 0"
definition "expand_new_name \<equiv> Suc"

lemma expand_new_name_expand_init:
  shows "\<forall>nm. expand_init < expand_new_name nm"
by (auto simp add:expand_init_def expand_new_name_def)

lemma expand_new_name_step[intro]:
  shows "\<And>n. name (n::'a node) < expand_new_name (name n)"
proof -
  fix n::"'a node"
  show "name n < expand_new_name (name n)" by (auto simp add:expand_new_name_def)
qed

lemma expand_new_name__less_zero[intro]: "0 < expand_new_name nm"
proof -
  from expand_new_name_expand_init have "expand_init < expand_new_name nm" by auto
  then show ?thesis by (metis gr0I less_zeroE)
qed

abbreviation
  "upd_incoming_f n \<equiv> (\<lambda>n'. 
    if (old n' = old n \<and> next n' = next n) then 
      n'\<lparr> incoming := incoming n \<union> incoming n' \<rparr> 
    else n'
  )"

definition
 "upd_incoming n ns \<equiv> ((upd_incoming_f n) ` ns)"

lemma upd_incoming__elem:
  assumes "nd\<in>upd_incoming n ns"
    shows "nd\<in>ns
           \<or> (\<exists>nd'\<in>ns. nd = nd'\<lparr> incoming := incoming n \<union> incoming nd' \<rparr> \<and>
                              old nd' = old n \<and>
                              next nd' = next n)"
proof -
  obtain nd' where "nd'\<in>ns" and nd_eq: "nd = upd_incoming_f n nd'" 
    using assms unfolding upd_incoming_def by blast
  then show ?thesis by auto
qed

lemma upd_incoming__ident_node:
  assumes "nd\<in>upd_incoming n ns" and "nd\<in>ns"
    shows "incoming n \<subseteq> incoming nd \<or> \<not> (old nd = old n \<and> next nd = next n)"
proof(rule ccontr)
  assume "\<not> ?thesis"
  then have nsubset: "\<not> (incoming n \<subseteq> incoming nd)" and 
    old_next_eq: "old nd = old n \<and> next nd = next n" 
    by auto
  moreover
  obtain nd' where "nd'\<in>ns" and nd_eq: "nd = upd_incoming_f n nd'" 
    using assms unfolding upd_incoming_def by blast
  { assume "old nd' = old n \<and> next nd' = next n"
    with nd_eq have "nd = nd'\<lparr>incoming := incoming n \<union> incoming nd'\<rparr>" by auto
    with nsubset have "False" by auto }
  moreover
  { assume "\<not> (old nd' = old n \<and> next nd' = next n)"
    with nd_eq old_next_eq have "False" by auto }
  ultimately show "False" by fast
qed

lemma upd_incoming__ident:
  assumes "\<forall>n\<in>ns. P n"
      and "\<And>n. \<lbrakk>n\<in>ns; P n\<rbrakk> \<Longrightarrow> (\<And>v. P (n\<lparr> incoming := v \<rparr>))"
    shows "\<forall>n\<in>upd_incoming n ns. P n"
proof
  fix nd v
  let ?f = "\<lambda>n'. 
    if (old n' = old n \<and> next n' = next n) then 
      n'\<lparr> incoming := incoming n \<union> incoming n' \<rparr> 
    else n'"
  assume "nd\<in>upd_incoming n ns"
  then obtain nd' where "nd'\<in>ns" and nd_eq: "nd = ?f nd'" 
    unfolding upd_incoming_def by blast
  { assume "old nd' = old n \<and> next nd' = next n"
    then obtain v where "nd = nd'\<lparr> incoming := v \<rparr>" using nd_eq by auto
    with assms `nd'\<in>ns` have "P nd" by auto }
  then show "P nd" using nd_eq `nd'\<in>ns` assms by auto
qed


lemma name_upd_incoming_f[simp]: "name (upd_incoming_f n x) = name x"
  by auto


lemma name_upd_incoming[simp]: 
  "name ` (upd_incoming n ns) = name ` ns" (is "?lhs = ?rhs")
  unfolding upd_incoming_def
proof safe
  fix x
  assume "x\<in>ns"
  then have "upd_incoming_f n x \<in> (\<lambda>n'. local.upd_incoming_f n n') ` ns" by auto
  then have "name (upd_incoming_f n x) \<in> name ` (\<lambda>n'. local.upd_incoming_f n n') ` ns"
    by blast
  then show "name x \<in> name ` (\<lambda>n'. local.upd_incoming_f n n') ` ns" by simp
qed auto


abbreviation expand_body
where
  "expand_body \<equiv> (\<lambda>expand (n,ns). 
      if new n = {} then ( 
        if (\<exists>n'\<in>ns. old n' = old n \<and> next n' = next n) then 
          RETURN (name n, upd_incoming n ns)
        else 
          expand ( 
            \<lparr> 
              name=expand_new_name (name n), 
              incoming={name n}, 
              new=next n, 
              old={}, 
              next={} 
            \<rparr>, 
            {n} \<union> ns) 
      ) else do { 
        \<phi> \<leftarrow> SPEC (\<lambda>x. x\<in>(new n));
        let n = n\<lparr> new := new n - {\<phi>} \<rparr>;
        if (\<exists>q. \<phi> = prop\<^sub>n(q) \<or> \<phi> = nprop\<^sub>n(q)) then
          (if (frml_neg \<phi>)\<in>old n then RETURN (name n, ns)
           else expand (n\<lparr> old := {\<phi>} \<union> old n \<rparr>, ns))
        else if \<phi> = true\<^sub>n then expand (n\<lparr> old := {\<phi>} \<union> old n \<rparr>, ns)
        else if \<phi> = false\<^sub>n then RETURN (name n, ns)
        else if (\<exists>\<nu> \<mu>. (\<phi> = \<nu> and\<^sub>n \<mu>) \<or> (\<phi> = X\<^sub>n \<nu>)) then 
          expand (
            n\<lparr> 
              new := new1 \<phi> \<union> new n, 
              old := {\<phi>} \<union> old n, 
              next := next1 \<phi> \<union> next n 
            \<rparr>, 
            ns)
        else do {
          (nm, nds) \<leftarrow> expand (
            n\<lparr> 
              new := new1 \<phi> \<union> new n, 
              old := {\<phi>} \<union> old n, 
              next := next1 \<phi> \<union> next n 
            \<rparr>, 
            ns);
          expand (n\<lparr> name := nm, new := new2 \<phi> \<union> new n, old := {\<phi>} \<union> old n \<rparr>, nds)
        }
      }
     )"

lemma expand_body_mono: "trimono expand_body" by refine_mono

definition expand :: "('a node \<times> ('a node set)) \<Rightarrow> (node_name \<times> 'a node set) nres"
  where "expand \<equiv> REC expand_body"

lemma REC_rule_old: (* TODO: Adapt proofs below, have fun with goal27 ...*)
  fixes x::"'x"
  assumes M: "trimono body"
  assumes I0: "\<Phi> x"
  assumes IS: "\<And>f x. \<lbrakk> \<And>x. \<Phi> x \<Longrightarrow> f x \<le> M x; \<Phi> x; f \<le> REC body \<rbrakk> 
    \<Longrightarrow> body f x \<le> M x"
  shows "REC body x \<le> M x"
  by (rule REC_rule_arb[where pre="\<lambda>_. \<Phi>" and M="\<lambda>_. M", OF assms])

lemma expand_rec_rule:
  assumes I0: "\<Phi> x"
  assumes IS: "\<And>f x. \<lbrakk> \<And>x. f x \<le> expand x; \<And>x. \<Phi> x \<Longrightarrow> f x \<le> M x; \<Phi> x \<rbrakk> 
    \<Longrightarrow> expand_body f x \<le> M x"
  shows "expand x \<le> M x"
  unfolding expand_def
  apply (rule REC_rule_old[where \<Phi>="\<Phi>"])
  apply (rule expand_body_mono)
  apply (rule I0)
  apply (rule IS[unfolded expand_def])
  apply (blast dest: le_funD)
  apply blast
  apply blast
  done

abbreviation
  "expand_assm_incoming n_ns
   \<equiv> (\<forall>nm\<in>incoming (fst n_ns). name (fst n_ns) > nm) 
    \<and> 0 < name (fst n_ns)
    \<and> (\<forall>q\<in>snd n_ns. 
        name (fst n_ns) > name q 
      \<and> (\<forall>nm\<in>incoming q. name (fst n_ns) > nm))"

abbreviation
  "expand_rslt_incoming nm_nds
   \<equiv> (\<forall>q\<in>snd nm_nds. (fst nm_nds > name q \<and> (\<forall>nm'\<in>incoming q. fst nm_nds > nm')))"

abbreviation
  "expand_rslt_name n_ns nm_nds
   \<equiv> (name (fst n_ns) \<le> fst nm_nds \<and> name ` (snd n_ns) \<subseteq> name ` (snd nm_nds))
     \<and> name ` (snd nm_nds) 
       = name ` (snd n_ns) \<union> name ` {nd\<in>snd nm_nds. name nd \<ge> name (fst n_ns)}"

abbreviation
  "expand_name_ident nds
   \<equiv> (\<forall>q\<in>nds. \<exists>!q'\<in>nds. name q = name q')"

abbreviation
  "expand_assm_exist \<xi> n_ns
   \<equiv> {\<eta>. \<exists>\<mu>. \<mu> U\<^sub>n \<eta> \<in> old (fst n_ns) \<and> \<xi> \<Turnstile>\<^sub>n \<eta>} \<subseteq> new (fst n_ns) \<union> old (fst n_ns)
         \<and> (\<forall>\<psi>\<in>new (fst n_ns). \<xi> \<Turnstile>\<^sub>n \<psi>) 
         \<and> (\<forall>\<psi>\<in>old (fst n_ns). \<xi> \<Turnstile>\<^sub>n \<psi>)
         \<and> (\<forall>\<psi>\<in>next (fst n_ns). \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)"

abbreviation
  "expand_rslt_exist__node_prop \<xi> n nd
   \<equiv> incoming n \<subseteq> incoming nd 
      \<and> (\<forall>\<psi>\<in>old nd. \<xi> \<Turnstile>\<^sub>n \<psi>) \<and> (\<forall>\<psi>\<in>next nd. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)
      \<and> {\<eta>. \<exists>\<mu>. \<mu> U\<^sub>n \<eta> \<in> old nd \<and> \<xi> \<Turnstile>\<^sub>n \<eta>} \<subseteq> old nd"

abbreviation
  "expand_rslt_exist \<xi> n_ns nm_nds
  \<equiv> (\<exists>nd\<in>snd nm_nds. expand_rslt_exist__node_prop \<xi> (fst n_ns) nd)"

abbreviation
  "expand_rslt_exist_eq__node n nd
   \<equiv> name n = name nd 
    \<and> old n = old nd 
    \<and> next n = next nd 
    \<and> incoming n \<subseteq> incoming nd"

abbreviation
  "expand_rslt_exist_eq n_ns nm_nds \<equiv> 
    (\<forall>n\<in>snd n_ns. \<exists>nd\<in>snd nm_nds. expand_rslt_exist_eq__node n nd)"

lemma expand_name_propag:
  assumes "expand_assm_incoming n_ns \<and> expand_name_ident (snd n_ns)" (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (\<lambda>r. expand_rslt_incoming r
                                    \<and> expand_rslt_name n_ns r
                                    \<and> expand_name_ident (snd r))"
      (is "expand _ \<le> SPEC (?P n_ns)")
using assms 
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case (goal1 _ _ n ns)
    then have Q: "?Q (n, ns)" by fast
    let ?nds = "upd_incoming n ns"

    have "\<forall>q\<in>?nds. name q < name n" using goal1 
      by (rule_tac upd_incoming__ident) auto
    moreover
    have "\<forall>q\<in>?nds. \<forall>nm'\<in>incoming q. nm' < name n" (is "\<forall>q\<in>_. ?sg q")
    proof
      fix q
      assume q_in:"q\<in>?nds"
      { assume "q\<in>ns"
        then have "?sg q" using goal1 by auto }
      moreover
      { assume "q\<notin>ns"
        with upd_incoming__elem[OF q_in]
        obtain nd' where 
          nd'_def:"nd'\<in>ns \<and> q = nd'\<lparr>incoming := incoming n \<union> incoming nd'\<rparr>"
        by blast

        { fix nm'
          assume "nm'\<in>incoming q"
          moreover
          { assume "nm'\<in>incoming n"
            with Q have "nm' < name n" by auto }
          moreover
          { assume "nm'\<in>incoming nd'"
            with Q nd'_def have "nm' < name n" by auto }
          ultimately have "nm' < name n" using nd'_def by auto }

        then have "?sg q" by fast }
      ultimately show "?sg q" by fast
    qed
    moreover
    have "expand_name_ident ?nds"
    proof (rule_tac upd_incoming__ident)
      case goal1 show ?case
        proof 
          fix q
          assume "q\<in>ns"
          
          with Q have "\<exists>!q'\<in>ns. name q = name q'" by auto
          then obtain q' where "q'\<in>ns" and "name q = name q'"
                           and q'_all: "\<forall>q''\<in>ns. name q' = name q'' \<longrightarrow> q' = q''"
            by auto
          let ?q' = "upd_incoming_f n q'"
          have P_a: "?q'\<in>?nds \<and> name q = name ?q'" 
            using `q'\<in>ns` `name q = name q'` q'_all
            unfolding upd_incoming_def by auto
          
          have P_all: "\<forall>q''\<in>?nds. name ?q' = name q'' \<longrightarrow> ?q' = q''"
          proof(clarify)
            fix q''
            assume "q''\<in>?nds" and q''_name_eq: "name ?q' = name q''"
            { assume "q''\<notin>ns"
              with upd_incoming__elem[OF `q''\<in>?nds`]
              obtain nd'' where 
                "nd''\<in>ns"
                and q''_is: "q'' = nd''\<lparr>incoming := incoming n \<union> incoming nd''\<rparr>
                              \<and> old nd'' = old n \<and> next nd'' = next n"
                by auto
              then have "name nd'' = name q'" 
                using q''_name_eq 
                by (cases "old q' = old n \<and> next q' = next n") auto
              with `nd''\<in>ns` q'_all have "nd'' = q'" by auto
              then have "?q' = q''" using q''_is by simp }
            moreover
            { assume "q''\<in>ns"
              moreover
              have "name q' = name q''" 
                using q''_name_eq 
                by (cases "old q' = old n \<and> next q' = next n") auto
              moreover
              then have "incoming n \<subseteq> incoming q'' 
                \<Longrightarrow> incoming q'' = incoming n \<union> incoming q''" 
                by auto
              ultimately have "?q' = q''" 
                using upd_incoming__ident_node[OF `q''\<in>?nds`] q'_all 
                by auto 
            }
            ultimately show "?q' = q''" by fast
          qed
          
          show "\<exists>!q'\<in>upd_incoming n ns. name q = name q'"
          proof(rule_tac ex1I[of _ ?q'])
            case goal1 then show ?case using P_a by simp
          next
            case goal2 then show ?case 
              using P_all unfolding P_a[THEN conjunct2, THEN sym] 
              by blast
          qed
        qed
    qed simp

    ultimately show ?case using goal1 by auto
next
  case (goal2 f _ n ns)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp
    have Q: "?Q (n, ns)" using goal2 by auto

    show ?case unfolding `x = (n, ns)`
    proof (rule_tac SPEC_rule_param2[where P = "?P"], rule_tac step)
      case goal1
        with expand_new_name_step[of n] show ?case 
          using Q 
          apply (auto elim: order_less_trans[rotated])
          done
    next
      case (goal2 _ nds)
        then have "name ` ns \<subseteq> name ` nds" using goal2 by auto
        with expand_new_name_step[of n] show ?case using goal2
          by auto
    qed
next
  case goal3 then show ?case using goal3 by auto
next
  case (goal4 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp+    
    show ?case using goal4 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal5 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp+
    show ?case using goal5 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp+
    show ?case using goal7 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)"
      by (cases \<psi>) auto
    have Q: "?Q (n, ns)" and step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" 
      using goal8 by simp+
    show ?case using goal_assms Q unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_nested2)
      case goal1 then show ?case
        by (rule_tac SPEC_rule_param2, rule_tac step) auto
    next
      case (goal2 nm nds)
        then have P_x: "(name n \<le> nm \<and> name ` ns \<subseteq> name ` nds)
                    \<and> name ` nds = name ` ns \<union> name ` {nd\<in>nds. name nd \<ge> name n}"
               (is "_ \<and> ?nodes_eq nds ns (name n)") by auto

        show ?case using goal2
        proof (rule_tac SPEC_rule_param2[where P = "?P"])
          case goal1 then show ?case by (rule_tac step) auto
        next
          case (goal2 nm' nds')
            then have "\<forall>q\<in>nds'. name q < nm' \<and> (\<forall>nm''\<in>incoming q. nm'' < nm')" by auto
            moreover
            have "?nodes_eq nds ns (name n)" and "?nodes_eq nds' nds nm"
             and "name n \<le> nm" using goal2 P_x by auto
            then have "?nodes_eq nds' ns (name n)" by auto
            then have "expand_rslt_name (n, ns) (nm', nds')"
            using goal2 P_x subset_trans[of "name ` ns" "name ` nds"] by auto
            ultimately show ?case using goal2 by auto
        qed
    qed
qed

lemmas expand_name_propag__incoming = SPEC_rule_conjunct1[OF expand_name_propag]
lemmas expand_name_propag__name = 
  SPEC_rule_conjunct1[OF SPEC_rule_conjunct2[OF expand_name_propag]]
lemmas expand_name_propag__name_ident = 
  SPEC_rule_conjunct2[OF SPEC_rule_conjunct2[OF expand_name_propag]]


lemma expand_rslt_exist_eq:
    shows "expand n_ns \<le> SPEC (expand_rslt_exist_eq n_ns)"
      (is "_ \<le> SPEC (?P n_ns)")
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="\<lambda>_. True"], simp, intro refine_vcg)
  case (goal1 f _ n ns)
    let ?r = "(name n, upd_incoming n ns)"
    have "expand_rslt_exist_eq (n, ns) ?r" unfolding snd_conv 
    proof
      fix n'
      assume "n'\<in>ns"
      { assume "old n' = old n \<and> next n' = next n"
        with `n'\<in>ns` 
        have "n'\<lparr> incoming := incoming n \<union> incoming n' \<rparr> \<in> upd_incoming n ns"
          unfolding upd_incoming_def by auto 
      }
      moreover
      { assume "\<not> (old n' = old n \<and> next n' = next n)"
        with `n'\<in>ns` have "n' \<in> upd_incoming n ns" 
          unfolding upd_incoming_def by auto 
      }
      ultimately show "\<exists>nd\<in>upd_incoming n ns. expand_rslt_exist_eq__node n' nd" 
        by force
    qed
    then show ?case using goal1 by auto
next
  case (goal2 f)
    then have step: "\<And>x. f x \<le> SPEC (?P x)" by simp
    show ?case using goal2 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal3 then show ?case by auto
next
  case (goal4 f)
    then have step: "\<And>x. f x \<le> SPEC (?P x)" by simp
    show ?case using goal4 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal5 f)
    then have step: "\<And>x. f x \<le> SPEC (?P x)" by simp
    show ?case using goal5 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f)
    then have step: "\<And>x. f x \<le> SPEC (?P x)" by simp
    show ?case using goal7 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal8 f x n ns)
  have step: "\<And>x. f x \<le> SPEC (?P x)" using goal8 by simp

  show ?case using goal8
  proof (rule_tac SPEC_rule_nested2)
    case goal1 then show ?case by (rule_tac SPEC_rule_param2, rule_tac step) auto
  next
    case (goal2 nm nds)
    have P_x: "?P (n, ns) (nm, nds)" using goal2 by fast
    
    show ?case unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_param2[where P = "?P"])
      case goal1 then show ?case by (rule_tac step)
    next
      case (goal2 nm' nds')
      { fix n'
        assume "n'\<in>ns"
        with P_x obtain nd where 
          "nd\<in>nds" and 
          n'_split: "expand_rslt_exist_eq__node n' nd" 
          by auto
        
        with goal2 obtain nd' where 
          "nd'\<in>nds'" 
          and "expand_rslt_exist_eq__node nd nd'"
          by auto
        then have "\<exists>nd'\<in>nds'. expand_rslt_exist_eq__node n' nd'"
          using n'_split subset_trans[of "incoming n'"] by auto 
      }
      then have "expand_rslt_exist_eq (n, ns) (nm', nds')" by auto
      then show ?case using goal2 by auto
    qed
  qed
qed 

lemma expand_prop_exist:
  shows "expand n_ns 
  \<le> SPEC (\<lambda>r. expand_assm_exist \<xi> n_ns \<longrightarrow> expand_rslt_exist \<xi> n_ns r)"
  (is "_ \<le> SPEC (?P n_ns)")
  using assms
proof (rule_tac expand_rec_rule[where \<Phi>="\<lambda>_. True"], simp, intro refine_vcg)
  case (goal1 f _ n ns)
    let ?nds = "upd_incoming n ns"
    let ?r = "(name n, ?nds)"
    { assume Q: "expand_assm_exist \<xi> (n, ns)"
      note `\<exists>n'\<in>ns. old n' = old n \<and> next n' = next n`
      then obtain n' where "n'\<in>ns" and assm_eq: "old n' = old n \<and> next n' = next n"
        by auto
      let ?nd = "n'\<lparr> incoming := incoming n \<union> incoming n'\<rparr>"
      have "?nd \<in> ?nds" using `n'\<in>ns` assm_eq unfolding upd_incoming_def by auto
      moreover
      have "incoming n \<subseteq> incoming ?nd" by auto
      moreover
      have "expand_rslt_exist__node_prop \<xi> n ?nd" using Q assm_eq `new n = {}` 
        by simp
      ultimately have "expand_rslt_exist \<xi> (n, ns) ?r" 
        unfolding fst_conv snd_conv by blast 
    }
    then show ?case using goal1 by auto
next
  case (goal2 f x n ns)
    then have step: "\<And>x. f x \<le> SPEC (?P x)"
      and f_sup: "\<And>x. f x \<le> expand x" by auto
    show ?case unfolding `x = (n, ns)`
    proof (rule_tac SPEC_rule_weak[where Q = "expand_rslt_exist_eq"])
      case goal1 then show ?case 
        by (rule_tac order_trans, rule_tac f_sup, rule_tac expand_rslt_exist_eq)
    next
      case goal2 then show ?case by (rule_tac step)
    next
      case (goal3 nm nds)
        then have "name ` ns \<subseteq> name ` nds" using goal3 by auto
        moreover
        { assume assm_ex: "expand_assm_exist \<xi> (n, ns)"
          then obtain nd where "nd\<in>nds" and "expand_rslt_exist_eq__node n nd"
          using goal3 by force+
          then have "expand_rslt_exist__node_prop \<xi> n nd"
           using assm_ex `new n = {}` by auto
          then have "expand_rslt_exist \<xi> (n, ns) (nm, nds)" using `nd\<in>nds` by auto }
        ultimately show ?case using expand_new_name_step[of n] goal3 by auto
    qed
next
  case (goal3 f x n ns \<psi>)
    { assume "expand_assm_exist \<xi> (n, ns)"
      then have "\<xi> \<Turnstile>\<^sub>n \<psi>" and "\<xi> \<Turnstile>\<^sub>n frml_neg \<psi>" using goal3 by auto
      then have "False" using goal3 by auto }
    then show ?case using goal3 by auto
next
  case (goal4 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>q. \<psi> = prop\<^sub>n(q) \<or> \<psi> = nprop\<^sub>n(q))"
      and step: "\<And>x. f x \<le> SPEC (?P x)" by simp+
    show ?case using goal_assms unfolding `x = (n, ns)`
    proof (rule_tac SPEC_rule_param2, rule_tac step)
       case (goal1 nm nds)
         { assume "expand_assm_exist \<xi> (n, ns)"
           then have "expand_rslt_exist \<xi> (n, ns) (nm, nds)" using goal1 by auto }
         then show ?case by auto
    qed
next
  case (goal5 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> \<psi> = true\<^sub>n"
      and step: "\<And>x. f x \<le> SPEC (?P x)" by simp+
    show ?case using goal_assms unfolding `x = (n, ns)`
    proof (rule_tac SPEC_rule_param2, rule_tac step)
       case (goal1 nm nds)
         { assume "expand_assm_exist \<xi> (n, ns)"
           then have "expand_rslt_exist \<xi> (n, ns) (nm, nds)" using goal1 by auto }
         then show ?case by auto
    qed
next
  case (goal6 f x n ns \<psi>)
    { assume "expand_assm_exist \<xi> (n, ns)"
      then have "\<xi> \<Turnstile>\<^sub>n false\<^sub>n" using goal6 by auto }
    then show ?case using goal6 by auto
next
  case (goal7 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)"
      and step: "\<And>x. f x \<le> SPEC (?P x)" by simp+
    show ?case using goal_assms unfolding `x = (n, ns)`
    proof (rule_tac SPEC_rule_param2, rule_tac step)
       case (goal1 nm nds)
         { assume "expand_assm_exist \<xi> (n, ns)"
           then have "expand_rslt_exist \<xi> (n, ns) (nm, nds)" using goal1 by auto }
         then show ?case by auto
    qed
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)"
      by (cases \<psi>) auto
    have step: "\<And>x. f x \<le> SPEC (?P x)"
      and f_sup: "\<And>x. f x \<le> expand x" using goal8 by auto
    let ?x1 = "(n\<lparr>new := new n - {\<psi>}, new := new1 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
                  old := {\<psi>} \<union> old n, next := next1 \<psi> \<union> next n\<rparr>, ns)"

    let ?new1_assm_sel = "\<lambda>\<psi>. (case \<psi> of \<mu> U\<^sub>n \<eta> => \<eta> | \<mu> V\<^sub>n \<eta> \<Rightarrow> \<mu> | \<mu> or\<^sub>n \<eta> \<Rightarrow> \<eta>)"

    { assume new1_assm: "\<not> (\<xi> \<Turnstile>\<^sub>n (?new1_assm_sel \<psi>))"
      then have ?case using goal_assms unfolding `x = (n, ns)`
      proof (rule_tac SPEC_rule_nested2)
        case goal1 then show ?case
          proof (rule_tac SPEC_rule_param2, rule_tac step)
            case (goal1 nm nds)
              { assume "expand_assm_exist \<xi> (n, ns)"
                with goal1 have "expand_assm_exist \<xi> ?x1" unfolding fst_conv 
                proof (cases \<psi>)
                  case (goal8 \<mu> \<eta>)
                    then have "\<xi> \<Turnstile>\<^sub>n \<mu> U\<^sub>n \<eta>" by fast
                    then have "\<xi> \<Turnstile>\<^sub>n \<mu>" and "\<xi> \<Turnstile>\<^sub>n X\<^sub>n (\<mu> U\<^sub>n \<eta>)" 
                      using goal8 ltln_expand_Until[of \<xi> \<mu> \<eta>] by auto
                    then show ?case using goal8 by auto
                next
                  case (goal9 \<mu> \<eta>)
                    then have "\<xi> \<Turnstile>\<^sub>n \<mu> V\<^sub>n \<eta>" by fast
                    moreover then have "\<xi> \<Turnstile>\<^sub>n \<eta>" and "\<xi> \<Turnstile>\<^sub>n X\<^sub>n (\<mu> V\<^sub>n \<eta>)" 
                      using goal9 ltln_expand_Release[of \<xi> \<mu> \<eta>] by auto
                    ultimately show ?case using goal9 by auto
                qed auto
                then have "expand_rslt_exist \<xi> (n, ns) (nm, nds)" using goal1 by force }
              then show ?case using goal1 by auto
          qed
      next
        case (goal2 nm nds)
          then have P_x: "?P (n, ns) (nm, nds)" by fast

          show ?case unfolding case_prod_unfold
          proof (rule_tac 
              SPEC_rule_weak[where P = "?P" and Q = "expand_rslt_exist_eq"])
            case goal1 then show ?case 
              by (rule_tac order_trans, 
                rule_tac f_sup, 
                rule_tac expand_rslt_exist_eq)
          next
            case goal2 then show ?case by (rule_tac step)
          next
            case (goal3 nm' nds')
              { assume "expand_assm_exist \<xi> (n, ns)"
                with P_x have "expand_rslt_exist \<xi> (n, ns) (nm, nds)" by simp
                then obtain nd where 
                  "nd\<in>nds" and "expand_rslt_exist__node_prop \<xi> n nd"
                using goal_assms by auto
                moreover
                with goal3 obtain nd' where 
                  "nd'\<in>nds'" and "expand_rslt_exist_eq__node nd nd'" 
                  by force
                ultimately have "expand_rslt_exist__node_prop \<xi> n nd'"
                using subset_trans[of "incoming n" "incoming nd"] by auto
                then have "expand_rslt_exist \<xi> (n,ns) (nm', nds')" 
                  using `nd'\<in>nds'` goal_assms by auto }
              then show ?case by fast
          qed
      qed }
    moreover
    { assume new1_assm: "\<xi> \<Turnstile>\<^sub>n (?new1_assm_sel \<psi>)" 
      let ?x2f = "\<lambda>(nm::node_name, nds::'a node set). (
          n\<lparr>new := new n - {\<psi>}, 
            name := nm, 
            new := new2 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
            old := {\<psi>} \<union> old n\<rparr>, 
          nds)"
      have P_x: "f ?x1 \<le> SPEC (?P ?x1)" by (rule step)
      moreover
      { fix r :: "node_name \<times> 'a node set"
        let ?x2 = "?x2f r"

        assume assm: "(?P ?x1) r"
        have  "f ?x2 \<le> SPEC (?P (n, ns))" unfolding case_prod_unfold fst_conv
        proof(rule_tac SPEC_rule_param2, rule_tac step)
          case (goal1 nm' nds')
            { assume "expand_assm_exist \<xi> (n, ns)"
              with new1_assm goal_assms have "expand_assm_exist \<xi> ?x2"
              proof (cases r, cases \<psi>)
                case (goal9 _ _ \<mu> \<eta>) 
                  then have "\<xi> \<Turnstile>\<^sub>n \<mu> V\<^sub>n \<eta>" unfolding fst_conv by fast
                  moreover with ltln_expand_Release[of \<xi> \<mu> \<eta>] have "\<xi> \<Turnstile>\<^sub>n \<eta>" by auto
                  ultimately show ?case using goal9 by auto
              qed auto
              with goal1 have "expand_rslt_exist \<xi> ?x2 (nm', nds')" 
                unfolding case_prod_unfold fst_conv snd_conv by fast
              then have "expand_rslt_exist \<xi> (n, ns) (nm', nds')" by (cases r, auto) }
            then show ?case by simp
        qed }
      then have "SPEC (?P ?x1) 
        \<le> SPEC (\<lambda>r. (case r of (nm, nds) => 
            f (?x2f (nm, nds))) \<le> SPEC (?P (n, ns)))" 
        using goal_assms by (rule_tac SPEC_rule) force
      finally have ?case unfolding case_prod_unfold `x = (n, ns)` by simp }
    ultimately show ?case by fast
qed



text {* Termination proof *}

definition expand\<^sub>T :: "('a node \<times> ('a node set)) \<Rightarrow> (node_name \<times> 'a node set) nres"
  where "expand\<^sub>T n_ns \<equiv> REC\<^sub>T expand_body n_ns"

abbreviation
  "old_next_pair n \<equiv> (old n, next n)"
 
abbreviation
  "old_next_limit \<phi> \<equiv> Pow (subfrmlsn \<phi>) \<times> Pow (subfrmlsn \<phi>)"

lemma old_next_limit_finite: "finite (old_next_limit \<phi>)" 
  using subfrmlsn_finite by auto

definition
  "expand_ord \<phi> \<equiv>
     inv_image (finite_psupset (old_next_limit \<phi>) <*lex*> less_than)
               (\<lambda>(n, ns). (old_next_pair ` ns, frmlset_sumn (new n)))"

lemma expand_ord_wf[simp]: "wf (expand_ord \<phi>)"
using finite_psupset_wf[OF old_next_limit_finite] unfolding expand_ord_def by auto

abbreviation
  "expand_inv_node \<phi> n 
  \<equiv> finite (new n) \<and> finite (old n) \<and> finite (next n) 
  \<and> (new n) \<union> (old n) \<union> (next n) \<subseteq> subfrmlsn \<phi>"

abbreviation
  "expand_inv_result \<phi> ns 
  \<equiv> finite ns \<and> (\<forall>n'\<in>ns. (new n') \<union> (old n') \<union> (next n') \<subseteq> subfrmlsn \<phi>)"

definition
  "expand_inv \<phi> n_ns 
  \<equiv> (case n_ns of (n, ns) \<Rightarrow> expand_inv_node \<phi> n \<and> expand_inv_result \<phi> ns)"

lemma new1_less_setsum: "frmlset_sumn (new1 \<phi>) < frmlset_sumn {\<phi>}"
proof (cases \<phi>, auto)
  fix \<nu> \<mu>
  show "frmlset_sumn {\<nu>,\<mu>} < Suc (size_frmln \<nu> + size_frmln \<mu>)"
  by (cases "\<nu> = \<mu>") auto
qed

lemma new2_less_setsum: "frmlset_sumn (new2 \<phi>) < frmlset_sumn {\<phi>}"
proof (cases \<phi>, auto)
  fix \<nu> \<mu>
  show "frmlset_sumn {\<nu>,\<mu>} < Suc (size_frmln \<nu> + size_frmln \<mu>)"
  by (cases "\<nu> = \<mu>") auto
qed

lemma new1_finite[intro]:"finite (new1 \<psi>)" by (cases \<psi>) auto
lemma new1_subset_frmls:"\<phi> \<in> new1 \<psi> \<Longrightarrow> \<phi> \<in> subfrmlsn \<psi>" by (cases \<psi>) auto

lemma new2_finite[intro]:"finite (new2 \<psi>)" by (cases \<psi>) auto
lemma new2_subset_frmls:"\<phi> \<in> new2 \<psi> \<Longrightarrow> \<phi> \<in> subfrmlsn \<psi>" by (cases \<psi>) auto

lemma next1_finite[intro]:"finite (next1 \<psi>)" by (cases \<psi>) auto
lemma next1_subset_frmls:"\<phi> \<in> next1 \<psi> \<Longrightarrow> \<phi> \<in> subfrmlsn \<psi>" by (cases \<psi>) auto

lemma "expand_inv_result \<phi> ns \<Longrightarrow> old_next_pair ` ns \<subseteq> old_next_limit \<phi>"
by auto

lemma expand_inv_impl[intro!]:
  assumes "expand_inv \<phi> (n, ns)"
      and newn:"\<psi>\<in>new n"
      and "old_next_pair ` ns \<subseteq> old_next_pair ` ns'"
      and "expand_inv_result \<phi> ns'"
      and "(n' = n\<lparr> new := new n - {\<psi>}, old := {\<psi>} \<union> old n \<rparr>) \<or>
           (n' = n\<lparr> new := new1 \<psi> \<union> (new n - {\<psi>}), 
                    old := {\<psi>} \<union> old n, 
                    next := next1 \<psi> \<union> next n \<rparr>) \<or>
           (n' = n\<lparr> name := nm, 
                    new := new2 \<psi> \<union> (new n - {\<psi>}), old := {\<psi>} \<union> old n \<rparr>)"
          (is "?case1 \<or> ?case2 \<or> ?case3")
    shows "((n', ns'), (n, ns))\<in>expand_ord \<phi> \<and> expand_inv \<phi> (n', ns')" 
          (is "?concl1 \<and> ?concl2")
proof
  { assume n'def:"?case1"
    with assms have "?concl1" 
      unfolding expand_inv_def expand_ord_def finite_psupset_def by auto 
  }
  moreover
  { assume n'def:"?case2"
    have \<psi>innew:"\<psi>\<in> new n" and fin_new:"finite (new n)"
      using assms unfolding expand_inv_def by auto
    from \<psi>innew setsum_diff1_nat[of size_frmln "new n" \<psi>]
    have "frmlset_sumn (new n - {\<psi>}) = frmlset_sumn (new n) - size_frmln \<psi>"  
      by simp
    moreover
    from fin_new setsum_Un_nat[OF new1_finite _, of "new n - {\<psi>}" size_frmln \<psi>]
    have "frmlset_sumn (new n') 
      \<le> frmlset_sumn (new1 \<psi>) + frmlset_sumn (new n - {\<psi>})"
      unfolding n'def by auto 
    moreover have sum_leq:"frmlset_sumn (new n) \<ge>  frmlset_sumn {\<psi>}"
      using \<psi>innew setsum_mono2[OF fin_new, of "{\<psi>}" size_frmln] 
        size_frmln_gt_zero 
      by simp
    ultimately have "frmlset_sumn (new n') < frmlset_sumn (new n)" 
      using new1_less_setsum[of \<psi>] sum_leq by auto
    then have ?concl1 using assms unfolding expand_ord_def finite_psupset_def by auto }
  moreover
  { assume n'def:"?case3"
    have \<psi>innew:"\<psi>\<in> new n" and fin_new:"finite (new n)"
      using assms unfolding expand_inv_def by auto
    from \<psi>innew setsum_diff1_nat[of size_frmln "new n" \<psi>]
    have "frmlset_sumn (new n - {\<psi>}) = frmlset_sumn (new n) - size_frmln \<psi>"
      by simp
    moreover
    from fin_new setsum_Un_nat[OF new2_finite _, of "new n - {\<psi>}" size_frmln \<psi>]
    have "frmlset_sumn (new n') 
      \<le> frmlset_sumn (new2 \<psi>) + frmlset_sumn (new n - {\<psi>})" 
      unfolding n'def by auto 
    moreover have sum_leq:"frmlset_sumn (new n) \<ge>  frmlset_sumn {\<psi>}"
      using \<psi>innew setsum_mono2[OF fin_new, of "{\<psi>}" size_frmln] 
        size_frmln_gt_zero 
      by simp
    ultimately have "frmlset_sumn (new n') < frmlset_sumn (new n)" 
      using new2_less_setsum[of \<psi>] sum_leq by auto
    then have ?concl1 using assms unfolding expand_ord_def finite_psupset_def by auto }
  ultimately show ?concl1 using assms by fast
next
  have "new1 \<psi> \<subseteq> subfrmlsn \<phi>" 
    and "new2 \<psi> \<subseteq> subfrmlsn \<phi>" 
    and "next1 \<psi> \<subseteq> subfrmlsn \<phi>"
  using assms subfrmlsn_subset[OF new1_subset_frmls[of _ \<psi>]]
              subfrmlsn_subset[of \<psi> \<phi>, OF set_rev_mp[of _ "new n"]]
              subfrmlsn_subset[OF new2_subset_frmls[of _ \<psi>]]
              subfrmlsn_subset[OF next1_subset_frmls[of _ \<psi>]] 
   unfolding expand_inv_def
   (* This proof is merely a speed optimization. A single force+ does the job, 
     but takes very long *)
   apply -
   apply (clarsimp split: prod.splits)
   apply (metis in_mono new1_subset_frmls)
   apply (clarsimp split: prod.splits)
   apply (metis new2_subset_frmls set_rev_mp)
   apply (clarsimp split: prod.splits)
   apply (metis in_mono next1_subset_frmls)
   done

  then show ?concl2 using assms 
    unfolding expand_inv_def 
    by auto
qed

lemma expand_term_prop_help:
  assumes "((n', ns'), (n, ns))\<in>expand_ord \<phi> \<and> expand_inv \<phi> (n', ns')"
  and assm_rule: "\<lbrakk>expand_inv \<phi> (n', ns'); ((n', ns'), n, ns) \<in> expand_ord \<phi>\<rbrakk>
    \<Longrightarrow> f (n', ns') \<le> SPEC P"
  shows "f (n', ns') \<le> SPEC P"
  using assms by (rule_tac assm_rule) auto

lemma expand_inv_upd_incoming:
  assumes "expand_inv \<phi> (n, ns)"
    shows "expand_inv_result \<phi> (upd_incoming n ns)"
using assms unfolding expand_inv_def upd_incoming_def by force


lemma upd_incoming_eq_old_next_pair:
  shows "old_next_pair ` ns = old_next_pair ` (upd_incoming n ns)" (is "?A = ?B")
proof
  { fix x
    let ?f = "\<lambda>n'. n'\<lparr>incoming := incoming n \<union> incoming n'\<rparr>"
    assume xin:"x\<in>old_next_pair ` ns"
    then obtain n' where "n'\<in>ns" and xeq:"x = (old n', next n')" by auto
    { 
      assume "old n' = old n \<and> next n' = next n"
      with `n'\<in>ns` 
      have "?f n'\<in>?f ` (ns \<inter> {n'\<in>ns. old n' = old n \<and> next n' = next n})"
        (is "_\<in>?A") 
        by auto
      then have "old_next_pair (?f n')\<in>old_next_pair ` ?A" 
        by (rule_tac imageI) auto
      with xeq have "x\<in>old_next_pair ` ?A" by auto }
    moreover 
    { assume "old n' \<noteq> old n \<or> next n' \<noteq> next n" (is "?cond n'")
      with `n'\<in>ns` xeq 
      have "x\<in>old_next_pair ` (ns \<inter> {n'\<in>ns. ?cond n'})" (is "_\<in>?A") 
        by auto 
    }
    ultimately have 
      "x\<in>(old_next_pair ` (\<lambda>n'. n'\<lparr>incoming := incoming n \<union> incoming n'\<rparr>) 
             ` (ns \<inter> {n' \<in> ns. old n' = old n \<and> next n' = next n}))
          \<union> (old_next_pair 
             ` (ns \<inter> {n' \<in> ns. old n' \<noteq> old n \<or> next n' \<noteq> next n}))" 
      by fast
    then have "x \<in> old_next_pair ` upd_incoming n ns" 
      using xin unfolding upd_incoming_def by auto 
  }
  then show "?A \<subseteq> ?B" by blast
next
  show "?B \<subseteq> ?A" unfolding upd_incoming_def by (force intro:imageI)
qed

lemma expand_term_prop:
    "expand_inv \<phi> n_ns 
  \<Longrightarrow> expand\<^sub>T n_ns \<le> SPEC (\<lambda>(_, nds). old_next_pair ` snd n_ns\<subseteq>old_next_pair `nds
    \<and> expand_inv_result \<phi> nds)"
  (is "_ \<Longrightarrow> _ \<le> SPEC (?P n_ns)")
  unfolding expand\<^sub>T_def
  apply (rule_tac RECT_rule[where 
    pre="\<lambda>(n, ns). expand_inv \<phi> (n, ns)" and
    V="expand_ord \<phi>"
    ])
  apply (refine_mono)
  apply simp
  apply simp
proof (intro refine_vcg)
  case (goal1 _ _  n ns)
    have "old_next_pair ` ns \<subseteq> old_next_pair ` (upd_incoming n ns)"
      by (rule equalityD1[OF upd_incoming_eq_old_next_pair])
    then show ?case using  expand_inv_upd_incoming[of \<phi> n ns] goal1 by auto
next
  case (goal2 expand _ n ns) 
    let ?n' = "\<lparr>
      name = expand_new_name (name n), 
      incoming = {name n}, 
      new = next n, 
      old = {}, 
      next = {}\<rparr>"
    let ?ns' = "{n} \<union> ns"
    have SPEC_sub:"SPEC (?P (?n', ?ns')) \<le> SPEC (?P x)" 
      using goal2 by (rule_tac SPEC_rule) auto
    from goal2 have "old_next_pair n\<notin>old_next_pair ` ns" by auto
    moreover then have subset_next_pair:
      "old_next_pair ` ns \<subset> old_next_pair ` (insert n ns)" 
      by auto
    ultimately have "((?n', ?ns'), (n, ns))\<in>expand_ord \<phi>" using goal2 
      by (auto simp add:expand_ord_def expand_inv_def finite_psupset_def)
    moreover have "expand_inv \<phi> (?n', ?ns')" 
      using goal2 unfolding expand_inv_def by auto
    ultimately have "expand (?n', ?ns') \<le> SPEC (?P (?n', ?ns'))" 
      using goal2 by fast
    with SPEC_sub show ?case apply (rule_tac order_trans) by fast+
next
  case goal3 then show ?case by (auto simp add:expand_inv_def)
next
  case goal4 then show ?case
    apply (rule_tac expand_term_prop_help[OF expand_inv_impl])
    apply (simp add:expand_inv_def)+
    apply force
    done
next
  case goal5 then show ?case
    apply (rule_tac expand_term_prop_help[OF expand_inv_impl])
    apply (simp add:expand_inv_def)+
    apply force
    done
next
  case goal6 then show ?case by (simp add:expand_inv_def)
next
  case goal7 then show ?case
    apply (rule_tac expand_term_prop_help[OF expand_inv_impl])
    apply (simp add:expand_inv_def)+
    apply force
    done
next
  case goal8
  let ?n' = "a\<lparr>
    new := new1 xa \<union> (new a - {xa}), 
    old := insert xa (old a), 
    next := next1 xa \<union> next a\<rparr>"
  let ?n'' = "\<lambda>nm. a\<lparr>
    name := nm, 
    new := new2 xa \<union> (new a - {xa}), 
    old := insert xa (old a)\<rparr>"
  have step:"((?n', b), (a, b)) \<in> expand_ord \<phi> \<and> expand_inv \<phi> (?n', b)" 
    using goal8
    by (rule_tac expand_inv_impl) (auto simp add:expand_inv_def)
  then have assm1: "f (?n', b) \<le> SPEC (?P (a, b))"
    using goal8 by auto
  moreover
  { fix nm::node_name and  nds::"'a node set"
    assume assm1: "old_next_pair ` b \<subseteq> old_next_pair ` nds"
      and assm2: "expand_inv_result \<phi> nds"
    then have "((?n'' nm, nds), (a, b)) \<in> expand_ord \<phi> 
      \<and> expand_inv \<phi> (?n'' nm, nds)" 
      using goal8 step
      by (rule_tac expand_inv_impl) auto
    then have "f (?n'' nm, nds) \<le> SPEC (?P (?n'' nm, nds))" using goal8 by auto
    moreover
    have "SPEC (?P (?n'' nm, nds)) \<le> SPEC (?P (a, b))" 
      using assm2 subset_trans[OF assm1] by auto
    ultimately have "f (?n'' nm, nds) \<le> SPEC (?P (a, b))" 
      by (rule order_trans) 
  }
  then have assm2: "SPEC (?P (a, b)) 
    \<le> SPEC (\<lambda>r. (case r of (nm, nds) \<Rightarrow> f (?n'' nm, nds)) \<le> SPEC (?P (a, b)))"
    by (rule_tac SPEC_rule) auto
  from order_trans[OF assm1 assm2] show ?case using goal8 by auto
qed

lemma expand_eq_expand\<^sub>T:
  assumes I: "expand_inv \<phi> n_ns"
    shows "expand\<^sub>T n_ns = expand n_ns"
  unfolding expand\<^sub>T_def expand_def
  apply (rule RECT_eq_REC)
  apply refine_mono
  unfolding expand\<^sub>T_def[symmetric]
  using expand_term_prop[OF I] by auto
  
lemma expand_nofail:
  assumes inv:"expand_inv \<phi> n_ns"
    shows "nofail (expand\<^sub>T n_ns)"
  using expand_term_prop[OF inv] by (simp add: pw_le_iff refine_pw_simps)

lemma [intro!]: "expand_inv \<phi> (
  \<lparr> 
    name = expand_new_name expand_init, 
    incoming = {expand_init}, 
    new = {\<phi>}, 
    old = {}, 
    next = {} \<rparr>, 
  {})"
by (auto simp add:expand_inv_def)

definition create_graph :: "'a frml \<Rightarrow> 'a node set nres"
where
  "create_graph \<phi> \<equiv> 
    do { 
      (_, nds) \<leftarrow> expand (
        \<lparr> 
          name = expand_new_name expand_init, 
          incoming = {expand_init}, 
          new = {\<phi>}, 
          old = {}, 
          next = {} 
        \<rparr>::'a node, 
        {}::'a node set);
      RETURN nds 
    }"

(* "expand_eq_expand\<^sub>T" *)

definition create_graph\<^sub>T :: "'a frml \<Rightarrow> 'a node set nres"
where
  "create_graph\<^sub>T \<phi> \<equiv> do { 
    (_, nds) \<leftarrow> expand\<^sub>T (
      \<lparr> 
        name = expand_new_name expand_init, 
        incoming = {expand_init}, 
        new = {\<phi>}, 
        old = {}, 
        next = {} 
      \<rparr>::'a node, 
    {}::'a node set);
    RETURN nds 
  }"

lemma create_graph_eq_create_graph\<^sub>T: "create_graph \<phi> = create_graph\<^sub>T \<phi>"
unfolding create_graph\<^sub>T_def create_graph_def
unfolding eq_iff
proof
  case goal1 then show ?case
    apply (refine_mono) unfolding expand_def expand\<^sub>T_def 
      by (rule REC_le_RECT)
next
  case goal2 then show ?case
    by (refine_mono, rule expand_eq_expand\<^sub>T[unfolded eq_iff, THEN conjunct1]) auto
qed


lemma create_graph_finite: "create_graph \<phi> \<le> SPEC finite"
proof -
  show ?thesis unfolding create_graph_def unfolding expand_def
    apply (intro refine_vcg)
    apply (rule_tac order_trans)
    apply (rule_tac REC_le_RECT)
    apply (fold expand\<^sub>T_def)
    apply (rule_tac order_trans[OF expand_term_prop]) 
    apply auto[1]
    apply (rule_tac SPEC_rule)
    apply auto
  done
qed

lemma create_graph_nofail: "nofail (create_graph \<phi>)"
by (rule_tac pwD1[OF create_graph_finite]) auto


abbreviation
  "create_graph_rslt_exist \<xi> nds
   \<equiv> \<exists>nd\<in>nds. 
        expand_init\<in>incoming nd 
      \<and> (\<forall>\<psi>\<in>old nd. \<xi> \<Turnstile>\<^sub>n \<psi>) \<and> (\<forall>\<psi>\<in>next nd. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)
      \<and> {\<eta>. \<exists>\<mu>. \<mu> U\<^sub>n \<eta> \<in> old nd \<and> \<xi> \<Turnstile>\<^sub>n \<eta>} \<subseteq> old nd"

lemma L4_7:
  assumes "\<xi> \<Turnstile>\<^sub>n \<phi>"
    shows "create_graph \<phi> \<le> SPEC (create_graph_rslt_exist \<xi>)"
  using assms unfolding create_graph_def
  by (intro refine_vcg, rule_tac order_trans, rule_tac expand_prop_exist) (
    auto simp add:expand_new_name_expand_init)


lemma expand_incoming_name_exist:
  assumes "name (fst n_ns) > expand_init 
  \<and> (\<forall>nm\<in>incoming (fst n_ns). nm \<noteq> expand_init \<longrightarrow> nm\<in>name ` (snd n_ns))
  \<and> expand_assm_incoming n_ns \<and> expand_name_ident (snd n_ns)" (is "?Q n_ns")
  and "\<forall>nd\<in>snd n_ns. 
    name nd > expand_init 
    \<and> (\<forall>nm\<in>incoming nd. nm \<noteq> expand_init \<longrightarrow> nm\<in>name ` (snd n_ns))" 
    (is "?P (snd n_ns)")
  shows "expand n_ns \<le> SPEC (\<lambda>nm_nds. ?P (snd nm_nds))"
  using assms
proof (
    rule_tac expand_rec_rule[where \<Phi>="\<lambda>n_ns. ?Q n_ns \<and> ?P (snd n_ns)"], 
    simp, 
    intro refine_vcg)
  case (goal1 f x n ns) then show ?case
  proof(simp, clarify)
    case (goal1 _ _ nd)
    { assume "nd\<in>ns"
      then have ?case using goal1 by auto }
    moreover
    { assume "nd\<notin>ns"
      with upd_incoming__elem[OF `nd\<in>upd_incoming n ns`]
      obtain nd' where "nd'\<in>ns" and "nd = nd'\<lparr>incoming :=
        incoming n \<union> incoming nd'\<rparr> \<and>
        old nd' = old n \<and>
        next nd' = next n" by auto
      then have ?case using goal1 by auto }
    ultimately show ?case by fast
  qed
next
  case (goal2 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x. ?P (snd x))"
      and QP: "?Q (n, ns) \<and> ?P ns" 
      and f_sup: "\<And>x. f x \<le> expand x" by auto
    show ?case unfolding `x = (n, ns)` using QP expand_new_name_expand_init
    proof (rule_tac step) 
      case goal1
        then have name_less: "name n < expand_new_name (name n)" by auto
        moreover then have "\<forall>nm\<in>incoming n. nm < expand_new_name (name n)" 
          using goal1 by auto
        moreover have "\<forall>q\<in>ns.
        name q < expand_new_name (name n) \<and>
        (\<forall>nm\<in>incoming q.
            nm < expand_new_name (name n))" using name_less goal1 by force
        moreover have "\<exists>!q'. (q' = n \<or> q' \<in> ns) \<and> name n = name q'" using QP 
          by force
        moreover have "\<forall>q\<in>ns.
       \<exists>!q'.
          (q' = n \<or> q' \<in> ns) \<and>
          name q = name q' " using QP by auto
        ultimately show ?case using goal1  by simp
    qed
next
  case goal3 then show ?case by simp
next
  case goal4 then show ?case by simp
next
  case goal5 then show ?case by simp
next
  case goal6 then show ?case by simp
next
  case goal7 then show ?case by simp
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: 
      "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)" 
      by (cases \<psi>) auto
    then have QP: "?Q (n, ns) \<and> ?P ns"
      and step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))"
      and f_sup: "\<And>x. f x \<le> expand x" using goal8 by auto
    let ?x = "(n\<lparr>new := new n - {\<psi>}, new := new1 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
          old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>), 
          next := next1 \<psi> \<union> next (n\<lparr>new := new n - {\<psi>}\<rparr>)\<rparr>, ns)"
    let ?props = "\<lambda>x r. expand_rslt_incoming r 
      \<and> expand_rslt_name x r 
      \<and> expand_name_ident (snd r)"

    show ?case using goal_assms QP unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_weak_nested2[where Q = "?props ?x"])
      case goal1 then show ?case 
        by (rule_tac order_trans, rule_tac f_sup, rule_tac expand_name_propag) simp
    next
      case goal2 then show ?case 
        by (rule_tac SPEC_rule_param2[where P = "\<lambda>x r. ?P (snd r)"], rule_tac step)
          auto
    next
      case (goal3 nm nds)
        then show ?case using goal3 
        proof (rule_tac SPEC_rule_weak[
            where P = "\<lambda>x r. ?P (snd r)" 
            and Q = "\<lambda>x r. expand_rslt_exist_eq x r \<and> ?props x r"])
          case goal1 then show ?case 
            by (rule_tac SPEC_rule_conjI, 
                   rule_tac order_trans, 
                   rule_tac f_sup, 
                   rule_tac expand_rslt_exist_eq,
                   rule_tac order_trans, 
                   rule_tac f_sup,
                   rule_tac expand_name_propag) force
        next
          case goal2 then show ?case 
            by (rule_tac SPEC_rule_param2[where P = "\<lambda>x r. ?P (snd r)"], 
              rule_tac step) force
        next
          case (goal3 nm' nds') then show ?case by simp
        qed
  qed
qed

lemma create_graph__incoming_name_exist:
  shows "create_graph \<phi> \<le> SPEC (\<lambda>nds. \<forall>nd\<in>nds. expand_init < name nd \<and> (\<forall>nm\<in>incoming nd. nm \<noteq> expand_init \<longrightarrow> nm\<in>name ` nds))"
  using assms unfolding create_graph_def
  by (intro refine_vcg, 
    rule_tac order_trans, 
    rule_tac expand_incoming_name_exist) (
    auto simp add:expand_new_name_expand_init)


abbreviation
  "expand_rslt_all__ex_equiv \<xi> nd nds \<equiv>
   (\<exists>nd'\<in>nds. 
    name nd \<in> incoming nd' 
    \<and> (\<forall>\<psi>\<in>old nd'. suffix 1 \<xi> \<Turnstile>\<^sub>n \<psi>) \<and> (\<forall>\<psi>\<in>next nd'. suffix 1 \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)
    \<and> {\<eta>. \<exists>\<mu>. \<mu> U\<^sub>n \<eta> \<in> old nd' \<and> suffix 1 \<xi> \<Turnstile>\<^sub>n \<eta>} \<subseteq> old nd')"

abbreviation
  "expand_rslt_all \<xi> n_ns nm_nds \<equiv>
   (\<forall>nd\<in>snd nm_nds. name nd \<notin> name ` (snd n_ns) \<and>
        (\<forall>\<psi>\<in>old nd. \<xi> \<Turnstile>\<^sub>n \<psi>) \<and> (\<forall>\<psi>\<in>next nd. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)
        \<longrightarrow> expand_rslt_all__ex_equiv \<xi> nd (snd nm_nds))"

lemma expand_prop_all:
  assumes "expand_assm_incoming n_ns \<and> expand_name_ident (snd n_ns)" (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (expand_rslt_all \<xi> n_ns)"
      (is "_ \<le> SPEC (?P n_ns)")
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case goal1 then show ?case by (simp, rule_tac upd_incoming__ident) simp+
next
  case (goal2 f x n ns)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)"
      and Q: "?Q (n, ns)" 
      and f_sup: "\<And>x. f x \<le> expand x" by auto
    let ?x = "(\<lparr>name = expand_new_name (name n), 
      incoming = {name n}, new = next n, old = {}, next = {}\<rparr>, {n} \<union> ns)"
    from Q have name_le: "name n < expand_new_name (name n)" by auto
    show ?case unfolding `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak[where 
        Q = "\<lambda>p r. 
        (expand_assm_exist (suffix 1 \<xi>) ?x \<longrightarrow> expand_rslt_exist (suffix 1 \<xi>) ?x r) 
        \<and> expand_rslt_exist_eq p r \<and> (expand_name_ident (snd r))"])
      case goal1 then show ?case
        proof (rule_tac SPEC_rule_conjI,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_prop_exist,
               rule_tac SPEC_rule_conjI,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_rslt_exist_eq,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_name_propag__name_ident)
          case goal1 then show ?case using Q name_le by force
        qed
    next
      case goal2 then show ?case using Q name_le by (rule_tac step) force
    next
      case (goal3 nm nds)
        then obtain n' where "n'\<in>nds" 
          and eq_node: "expand_rslt_exist_eq__node n n'" by auto
        with goal3 have ex1_name: "\<exists>!q\<in>nds. name n = name q" by auto
        then have nds_eq: "nds = {n'} \<union> {x \<in> nds. name n \<noteq> name x}" 
          using eq_node `n'\<in>nds` by blast
        have name_notin: "name n \<notin> name ` ns" using Q by auto
        have P_x: "expand_rslt_all \<xi> ?x (nm, nds)" using goal3 by fast

        show ?case unfolding snd_conv 
        proof(clarify)
          fix nd
          assume "nd \<in> nds" and name_img: "name nd \<notin> name ` ns"
             and nd_old_equiv: "\<forall>\<psi>\<in>old nd. \<xi> \<Turnstile>\<^sub>n \<psi>" 
            and nd_next_equiv: "\<forall>\<psi>\<in>next nd. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>"
          { assume "name nd = name n"
            with nds_eq eq_node `nd\<in>nds` have "nd = n'" by auto
            with goal3(1)[THEN conjunct1, simplified] 
              nd_old_equiv nd_next_equiv eq_node
            have "expand_rslt_all__ex_equiv \<xi> nd nds" by simp }
          moreover
          { assume "name nd \<noteq> name n"
            with name_img `nd \<in> nds` nd_old_equiv nd_next_equiv P_x
            have "expand_rslt_all__ex_equiv \<xi> nd nds" by simp }
          ultimately show "expand_rslt_all__ex_equiv \<xi> nd nds" by fast
        qed
    qed
next
  case goal3 then show ?case by auto
next
  case (goal4 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp+
    show ?case using goal4 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal5 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp+
    show ?case using goal5 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)" by simp+
    show ?case using goal7 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)"
      by (cases \<psi>) auto
    have Q: "?Q (n, ns)"
     and step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC (?P x)"
     and f_sup: "\<And>x. f x \<le> expand x" using goal8 by auto
    let ?x = "(n\<lparr>new := new n - {\<psi>}, new := new1 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
            old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>), 
                              next := next1 \<psi> \<union> next (n\<lparr>new := new n - {\<psi>}\<rparr>)
          \<rparr>, ns)"
    let ?props = "\<lambda>x r. expand_rslt_incoming r 
      \<and> expand_rslt_name x r 
      \<and> expand_name_ident (snd r)"

    show ?case using goal_assms Q unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_weak_nested2[where Q = "?props ?x"])
      case goal1 then show ?case by (rule_tac order_trans, 
        rule_tac f_sup, 
        rule_tac expand_name_propag) simp
    next
      case goal2 then show ?case 
        by (rule_tac SPEC_rule_param2[where P = "?P"], rule_tac step) auto
    next
      case (goal3 nm nds)
        then show ?case using goal3 
        proof (rule_tac SPEC_rule_weak[where 
            P = "?P" and 
            Q = "\<lambda>x r. expand_rslt_exist_eq x r \<and> ?props x r"])
          case goal1 then show ?case 
            by (rule_tac SPEC_rule_conjI, 
                   rule_tac order_trans, 
                   rule_tac f_sup, 
                   rule_tac expand_rslt_exist_eq,
                   rule_tac order_trans, 
                   rule_tac f_sup,
                   rule_tac expand_name_propag) auto
        next
          case goal2 then show ?case 
            by (rule_tac SPEC_rule_param2[where P = "?P"], rule_tac step) auto
        next
          case (goal3 nm' nds')
            then have P_x: "?P (n, ns) (nm, nds)"
              and P_x': "?P (n, nds) (nm', nds')" by simp+
            show ?case unfolding snd_conv
            proof(clarify)
              fix nd
              assume "nd\<in>nds'" and 
                name_nd_notin: "name nd \<notin> name ` ns" and
                old_equiv: "\<forall>\<psi>\<in>old nd. \<xi> \<Turnstile>\<^sub>n \<psi>" and 
                next_equiv: "\<forall>\<psi>\<in>next nd. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>"

              { assume "name nd \<in> name ` nds"
                then obtain n' where "n' \<in> nds" and "name nd = name n'" by auto
                then obtain nd' where "nd'\<in>nds'" 
                  and nd'_eq: "expand_rslt_exist_eq__node n' nd'" 
                  using goal3 by auto
                moreover have "\<forall>q\<in>nds'. \<exists>!q'\<in>nds'. name q = name q'" 
                  using goal3 by simp
                ultimately have "nd' = nd" using `name nd = name n'` `nd \<in> nds'` 
                  by auto
                with nd'_eq have n'_eq: "expand_rslt_exist_eq__node n' nd" by simp
                then have "name n'\<notin>name ` ns" 
                  and "\<forall>\<psi>\<in>old n'. \<xi> \<Turnstile>\<^sub>n \<psi>" and "\<forall>\<psi>\<in>next n'. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>"
                  using name_nd_notin old_equiv next_equiv `n' \<in> nds` 
                  by auto
                then have "expand_rslt_all__ex_equiv \<xi> n' nds" 
                  (is "\<exists>nd'\<in>nds. ?sthm n' nd'")
                using P_x `n' \<in> nds` unfolding snd_conv by blast
                then obtain sucnd where "sucnd\<in>nds" and sthm: "?sthm n' sucnd"
                  by blast
                moreover then obtain sucnd' where "sucnd'\<in>nds'" and 
                  sucnd'_eq: "expand_rslt_exist_eq__node sucnd sucnd'" 
                  using goal3 by auto
                ultimately have "?sthm n' sucnd'" by auto
                then have "expand_rslt_all__ex_equiv \<xi> nd nds'" using `sucnd'\<in>nds'`
                unfolding `name nd = name n'` by blast }
              moreover
              { assume "name nd \<notin> name ` nds"
                with `nd\<in>nds'` P_x' old_equiv next_equiv
                have "expand_rslt_all__ex_equiv \<xi> nd nds'" 
                  unfolding snd_conv by blast }
              ultimately show "expand_rslt_all__ex_equiv \<xi> nd nds'" by fast
            qed
        qed
    qed
qed

abbreviation
  "create_graph_rslt_all \<xi> nds
   \<equiv> \<forall>q\<in>nds. (\<forall>\<psi>\<in>old q. \<xi> \<Turnstile>\<^sub>n \<psi>) \<and> (\<forall>\<psi>\<in>next q. \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)
    \<longrightarrow> (\<exists>q'\<in>nds. name q \<in> incoming q'
         \<and> (\<forall>\<psi>\<in>old q'. suffix 1 \<xi> \<Turnstile>\<^sub>n \<psi>) 
         \<and> (\<forall>\<psi>\<in>next q'. suffix 1 \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>)
         \<and> {\<eta>. \<exists>\<mu>. \<mu> U\<^sub>n \<eta> \<in> old q' \<and> suffix 1 \<xi> \<Turnstile>\<^sub>n \<eta>} \<subseteq> old q')"

lemma L4_5:
  shows "create_graph \<phi> \<le> SPEC (create_graph_rslt_all \<xi>)"
  unfolding create_graph_def
  by (intro refine_vcg, 
    rule_tac order_trans, 
    rule_tac expand_prop_all) (auto simp add:expand_new_name_expand_init)

subsection {* Creation of GBA *}
text {* This section formalizes the second part of the algorithm, that creates
  the actual generalized B\"uchi automata from the set of nodes. *}

definition create_gba_from_nodes
  :: "'a frml \<Rightarrow> 'a node set \<Rightarrow> ('a node, 'a set) gba_rec"
where "create_gba_from_nodes \<phi> qs \<equiv> \<lparr> 
  g_V = qs,
  g_E = {(q, q'). q\<in>qs \<and> q'\<in>qs \<and> name q\<in>incoming q'},
  g_V0 = {q\<in>qs. expand_init\<in>incoming q},
  gbg_F = {{q\<in>qs. \<mu> U\<^sub>n \<eta>\<in>old q \<longrightarrow> \<eta>\<in>old q}|\<mu> \<eta>. \<mu> U\<^sub>n \<eta> \<in> subfrmlsn \<phi>},
  gba_L = \<lambda>q l. q\<in>qs \<and> {p. prop\<^sub>n(p)\<in>old q}\<subseteq>l \<and> {p. nprop\<^sub>n(p)\<in>old q} \<inter> l = {}
\<rparr>"

end

locale create_gba_from_nodes_precond =
  fixes \<phi> :: "'a ltln"
  fixes qs :: "'a node set"
  assumes res: "inres (create_graph \<phi>) qs"
begin

  lemma finite_qs[simp, intro!]: "finite qs"
    using res create_graph_finite by (auto simp add: refine_pw_simps pw_le_iff)

  lemma create_gba_from_nodes__invar: "gba (create_gba_from_nodes \<phi> qs)"
    using [[simproc finite_Collect]]
    apply unfold_locales 
    apply (auto
      intro!: finite_vimageI subfrmlsn_finite injI
      simp: create_gba_from_nodes_def)
    done

  sublocale gba!: gba "create_gba_from_nodes \<phi> qs" using create_gba_from_nodes__invar .

  lemma create_gba_from_nodes__fin: "finite (g_V (create_gba_from_nodes \<phi> qs))"
    unfolding create_gba_from_nodes_def by auto

  lemma create_gba_from_nodes__ipath:
    shows "ipath gba.E r
      \<longleftrightarrow> (\<forall>i. r i \<in>qs \<and> name (r i)\<in>incoming (r (Suc i)))"
    unfolding create_gba_from_nodes_def ipath_def
    by auto

  lemma create_gba_from_nodes__is_run:
    shows "gba.is_run r
           \<longleftrightarrow> expand_init \<in> incoming (r 0)
                \<and> (\<forall>i. r i\<in>qs \<and> name (r i)\<in>incoming (r (Suc i)))"
    unfolding gba.is_run_def
    apply (simp add: create_gba_from_nodes__ipath)
    apply (auto simp: create_gba_from_nodes_def)
    done

context begin interpretation LTL_Syntax .

abbreviation
  "auto_run_j j \<xi> q \<equiv> 
        (\<forall>\<psi>\<in>old q. suffix j \<xi> \<Turnstile>\<^sub>n \<psi>) \<and> (\<forall>\<psi>\<in>next q. suffix j \<xi> \<Turnstile>\<^sub>n X\<^sub>n \<psi>) \<and>
        {\<eta>. \<exists>\<mu>. \<mu> U\<^sub>n \<eta> \<in> old q \<and> suffix j \<xi> \<Turnstile>\<^sub>n \<eta>} \<subseteq> old q"

fun auto_run :: "['a interprt, 'a node set] \<Rightarrow> 'a node word"
where
  "auto_run \<xi> nds 0
   = (SOME q. q\<in>nds \<and> expand_init \<in> incoming q \<and> auto_run_j 0 \<xi> q)"
| "auto_run \<xi> nds (Suc k)
   = (SOME q'. q'\<in>nds \<and> name (auto_run \<xi> nds k) \<in> incoming q' 
        \<and> auto_run_j (Suc k) \<xi> q')"


(* TODO: Remove. Only special instance of more generic principle
lemma create_graph_comb:
  assumes "\<And>x. inres (create_graph \<phi>) x \<Longrightarrow> P x"
    shows "create_graph \<phi>\<le>SPEC P"
  using create_graph_nofail assms
  by (auto simp add: pw_le_iff refine_pw_simps)
*)

lemma run_propag_on_create_graph:
  assumes "ipath gba.E \<sigma>"
    shows "\<sigma> k\<in>qs \<and> name (\<sigma> k)\<in>incoming (\<sigma> (k+1))"
  using assms
  by (auto simp: create_gba_from_nodes__ipath)

lemma expand_false_propag:
  assumes "false\<^sub>n \<notin> old (fst n_ns) \<and> (\<forall>nd\<in>snd n_ns. false\<^sub>n \<notin> old nd)" 
  (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (\<lambda>nm_nds. \<forall>nd\<in>snd nm_nds. false\<^sub>n \<notin> old nd)"
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case goal1 then show ?case by (simp, rule_tac upd_incoming__ident) auto
next
  case goal8 then show ?case by (rule_tac SPEC_rule_nested2) auto
qed auto

lemma false_propag_on_create_graph:
  shows "create_graph \<phi> \<le> SPEC (\<lambda>nds. \<forall>nd\<in>nds. false\<^sub>n \<notin> old nd)"
unfolding create_graph_def
by (intro refine_vcg, rule_tac order_trans, rule_tac expand_false_propag) auto


lemma expand_and_propag:
  assumes "\<mu> and\<^sub>n \<eta> \<in> old (fst n_ns) 
  \<longrightarrow> {\<mu>, \<eta>} \<subseteq> old (fst n_ns) \<union> new (fst n_ns)" (is "?Q n_ns")
  and "\<forall>nd\<in>snd n_ns. \<mu> and\<^sub>n \<eta> \<in> old nd \<longrightarrow> {\<mu>, \<eta>} \<subseteq> old nd" (is "?P (snd n_ns)")
  shows "expand n_ns \<le> SPEC (\<lambda>nm_nds. ?P (snd nm_nds))"
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="\<lambda>x. ?Q x \<and> ?P (snd x)"], 
    simp, intro refine_vcg)
  case goal1 then show ?case by (simp, rule_tac upd_incoming__ident) auto
next
  case (goal4 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" by simp
    then show ?case using goal4 by (rule_tac step) auto
next
  case (goal5 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" by simp
    then show ?case using goal5 by (rule_tac step) auto
next
  case (goal6 f x n ns) then show ?case by auto
next
  case (goal7 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" by simp
    then show ?case using goal7 by (rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n 
      \<and> \<not> (\<exists>q. \<psi> = prop\<^sub>n(q) \<or> \<psi> = nprop\<^sub>n(q)) 
      \<and> \<psi> \<noteq> true\<^sub>n \<and> \<psi> \<noteq> false\<^sub>n 
      \<and> \<not> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)
      \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)" 
      by (cases \<psi>) auto
    have QP: "?Q (n, ns) \<and> ?P ns" 
      and step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" 
      using goal8 by simp+
    show ?case using goal_assms QP unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_nested2)
      case goal1 then show ?case by (rule_tac step) auto
    next
      case goal2 then show ?case by (rule_tac step) auto
    qed
qed auto

lemma and_propag_on_create_graph:
  shows "create_graph \<phi> 
  \<le> SPEC (\<lambda>nds. \<forall>nd\<in>nds. \<mu> and\<^sub>n \<eta> \<in> old nd \<longrightarrow> {\<mu>, \<eta>} \<subseteq> old nd)"
  unfolding create_graph_def
  by (intro refine_vcg, rule_tac order_trans, rule_tac expand_and_propag) auto


lemma expand_or_propag:
  assumes "\<mu> or\<^sub>n \<eta> \<in> old (fst n_ns) 
  \<longrightarrow> {\<mu>, \<eta>} \<inter> (old (fst n_ns) \<union> new (fst n_ns)) \<noteq> {}" (is "?Q n_ns")
  and "\<forall>nd\<in>snd n_ns. \<mu> or\<^sub>n \<eta> \<in> old nd \<longrightarrow> {\<mu>, \<eta>} \<inter> old nd \<noteq> {}" 
  (is "?P (snd n_ns)")
    shows "expand n_ns \<le> SPEC (\<lambda>nm_nds. ?P (snd nm_nds))"
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="\<lambda>x. ?Q x \<and> ?P (snd x)"], 
    simp, intro refine_vcg)
  case goal1 then show ?case by (simp, rule_tac upd_incoming__ident) auto
next
  case (goal4 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" by simp
    then show ?case using goal4 by (rule_tac step) auto
next
  case (goal5 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" by simp
    then show ?case using goal5 by (rule_tac step) auto
next
  case (goal6 f x n ns) then show ?case by auto
next
  case (goal7 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" by simp
    then show ?case using goal7 by (rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n 
      \<and> \<not> (\<exists>q. \<psi> = prop\<^sub>n(q) \<or> \<psi> = nprop\<^sub>n(q)) 
      \<and> \<psi> \<noteq> true\<^sub>n \<and> \<psi> \<noteq> false\<^sub>n 
      \<and> \<not> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)
      \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)" 
      by (cases \<psi>) auto
    have QP: "?Q (n, ns) \<and> ?P ns" 
      and step: "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>x'. ?P (snd x'))" 
      using goal8 by simp+
    show ?case using goal_assms QP unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_nested2)
      case goal1 then show ?case by (rule_tac step) auto
    next
      case goal2 then show ?case by (rule_tac step) auto
    qed
qed auto

lemma or_propag_on_create_graph:
  shows "create_graph \<phi> 
  \<le> SPEC (\<lambda>nds. \<forall>nd\<in>nds. \<mu> or\<^sub>n \<eta> \<in> old nd \<longrightarrow> {\<mu>, \<eta>} \<inter> old nd \<noteq> {})"
  unfolding create_graph_def
  by (intro refine_vcg, rule_tac order_trans, rule_tac expand_or_propag) auto


abbreviation
  "next_propag__assm \<mu> n_ns \<equiv>
     (X\<^sub>n \<mu> \<in> old (fst n_ns) \<longrightarrow> \<mu> \<in> next (fst n_ns))
     \<and> (\<forall>nd\<in>snd n_ns. X\<^sub>n \<mu> \<in> old nd \<and> name nd \<in> incoming (fst n_ns) 
        \<longrightarrow> \<mu> \<in> old (fst n_ns) \<union> new (fst n_ns))"

abbreviation
  "next_propag__rslt \<mu> ns \<equiv>
     \<forall>nd\<in>ns. \<forall>nd'\<in>ns. X\<^sub>n \<mu> \<in> old nd \<and> name nd \<in> incoming nd' \<longrightarrow> \<mu> \<in> old nd'"

lemma expand_next_propag:
  fixes n_ns :: "_ \<times> 'a node set"
  assumes "next_propag__assm \<mu> n_ns
           \<and> next_propag__rslt \<mu> (snd n_ns)
           \<and> expand_assm_incoming n_ns
           \<and> expand_name_ident (snd n_ns)" (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (\<lambda>r. next_propag__rslt \<mu> (snd r))"
      (is "_ \<le> SPEC ?P")
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case (goal1 f x n ns)
    then show ?case
    proof (simp, rule_tac upd_incoming__ident)
      case goal1
        { fix nd :: "'a node" and nd' :: "'a node"
          let ?X_prop = "X\<^sub>n \<mu> \<in> old nd \<and> name nd \<in> incoming nd'
                               \<longrightarrow> \<mu> \<in> old nd'"
          assume "nd\<in>ns" and nd'_elem: "nd'\<in>upd_incoming n ns"
          { assume "nd'\<in>ns"
            then have ?X_prop using `nd\<in>ns` goal1 by auto }
          moreover
          { assume "nd'\<notin>ns" and X_in_nd: "X\<^sub>n \<mu>\<in>old nd" and "name nd \<in>incoming nd'"
            with upd_incoming__elem[of nd' n ns] nd'_elem
            obtain nd'' where "nd''\<in>ns"
              and nd'_eq: "nd' = nd''\<lparr>incoming := incoming n \<union> incoming nd''\<rparr>"
              and old_eq: "old nd'' = old n" by auto
            { assume "name nd \<in> incoming n"
              with X_in_nd `nd\<in>ns` have "\<mu> \<in> old n" using goal1 by auto
              then have "\<mu> \<in> old nd'" using nd'_eq old_eq by simp }
            moreover
            { assume "name nd \<notin> incoming n"
              then have "name nd \<in> incoming nd''" 
                using `name nd \<in>incoming nd'` nd'_eq by simp
              then have "\<mu> \<in> old nd'" unfolding nd'_eq
              using `nd\<in>ns` `nd''\<in>ns` X_in_nd goal1 by auto }
            ultimately have "\<mu> \<in> old nd'" by fast }
          ultimately have ?X_prop by auto }
        then show ?case by auto
    next
      case goal2 then show ?case by simp
    qed
next
  case (goal2 f x n ns)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and f_sup: "\<And>x. f x \<le> expand x" by auto
    have Q: "?Q (n, ns)" using goal2 by auto
    from Q have name_le: "name n < expand_new_name (name n)" by auto
    let ?x' = "(\<lparr>name = expand_new_name (name n),
                 incoming = {name n}, new = next n,
                 old = {}, next = {}\<rparr>, {n} \<union> ns)"
    have Q'1: "expand_assm_incoming ?x'\<and> expand_name_ident (snd ?x')"
    using `new n = {}` Q[THEN conjunct2, THEN conjunct2] name_le by force
    have Q'2: "next_propag__assm \<mu> ?x' \<and> next_propag__rslt \<mu> (snd ?x')" 
      using Q `new n = {}` by auto

    show ?case using `new n = {}` unfolding `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak[where 
        Q = "\<lambda>_ r. expand_name_ident (snd r)" and P = "\<lambda>_. ?P"])
      case goal1 then show ?case using Q'1
        by (rule_tac order_trans, 
          rule_tac f_sup, 
          rule_tac expand_name_propag__name_ident) auto
    next
      case goal2 then show ?case using Q'1 Q'2 by (rule_tac step) simp
    next
      case (goal3 nm nds) then show ?case by simp
    qed
next
  case goal3 then show ?case by auto
next
  case (goal4 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal4 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal5 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal5 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal7 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)"
      by (cases \<psi>) auto
    have Q: "?Q (n, ns)"
     and step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
     and f_sup: "\<And>x. f x \<le> expand x" using goal8 by auto
    let ?x = "(n\<lparr>new := new n - {\<psi>}, new := new1 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
          old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>), 
                              next := next1 \<psi> \<union> next (n\<lparr>new := new n - {\<psi>}\<rparr>)
          \<rparr>, ns)"
    let ?props = "\<lambda>x r. expand_rslt_exist_eq x r 
      \<and> expand_rslt_incoming r \<and> expand_rslt_name x r \<and> expand_name_ident (snd r)"

    show ?case using goal_assms Q unfolding case_prod_unfold `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak_nested2[where Q = "?props ?x"])
      case goal1 then show ?case
        by (rule_tac SPEC_rule_conjI,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_rslt_exist_eq,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_name_propag) simp+
    next
      case goal2 then show ?case 
        by (rule_tac SPEC_rule_param2[where P = "\<lambda>_. ?P"], rule_tac step) auto
    next
      case (goal3 nm nds)
        let ?x' = "(n\<lparr>new := new n - {\<psi>},
           name := fst (nm, nds),
           new := new2 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
           old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>)\<rparr>, nds)"
        show ?case using goal3
        proof (rule_tac step)
          case goal1
            then have "expand_assm_incoming ?x'" by auto
            moreover
            have nds_ident: "expand_name_ident (snd ?x')" using goal1 by simp
            moreover
            have "X\<^sub>n \<mu> \<in> old (fst ?x') \<longrightarrow> \<mu>\<in>next (fst ?x')"
            using Q[THEN conjunct1] goal_assms by auto
            moreover
            have "next_propag__rslt \<mu> (snd ?x')" using goal1 by simp
            moreover
            have name_nds_eq: 
              "name ` nds = name ` ns \<union> name ` {nd\<in>nds. name nd \<ge> name n}" 
              using goal1 by auto
            have "\<forall>nd\<in>nds. (X\<^sub>n \<mu> \<in> old nd \<and> name nd \<in> incoming (fst ?x'))
                             \<longrightarrow> \<mu>\<in>old (fst ?x')\<union>new (fst ?x')"
             (is "\<forall>nd\<in>nds. ?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd")
            proof
              fix nd
              assume "nd\<in>nds"
              { assume loc_assm: "name nd\<in>name ` ns"
                then obtain n' where "n'\<in>ns" and "name n' = name nd" by auto
                moreover then obtain nd' where "nd'\<in>nds" 
                  and n'_nd'_eq: "expand_rslt_exist_eq__node n' nd'" 
                  using goal1 by auto
                ultimately have "nd = nd'" 
                  using nds_ident `nd\<in>nds` loc_assm by auto
                moreover from goal1 have "?assm n n' \<longrightarrow> ?concl n n'" 
                  using `n'\<in>ns` by auto
                ultimately have "?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd"
                  using n'_nd'_eq by auto }
              moreover
              { assume "name nd\<notin>name ` ns"
                with name_nds_eq `nd\<in>nds` have "name nd \<ge> name n" by auto
                then have "\<not> (?assm (fst ?x') nd)" using goal1 by auto }
              ultimately show "?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd" by auto
            qed
            ultimately show ?case by simp
        qed
    qed    
qed

lemma next_propag_on_create_graph:
  shows "create_graph \<phi>
    \<le> SPEC (\<lambda>nds. \<forall>n\<in>nds. \<forall>n'\<in>nds. X\<^sub>n \<mu>\<in>old n \<and> name n\<in>incoming n' \<longrightarrow> \<mu>\<in>old n')"
  unfolding create_graph_def
  by (intro refine_vcg, 
    rule_tac order_trans, 
    rule_tac expand_next_propag) (auto simp add:expand_new_name_expand_init)


abbreviation
  "release_propag__assm \<mu> \<eta> n_ns \<equiv>
     (\<mu> V\<^sub>n \<eta> \<in> old (fst n_ns)
      \<longrightarrow> {\<mu>, \<eta>}\<subseteq>old (fst n_ns)\<union>new (fst n_ns) \<or>
         (\<eta>\<in>old (fst n_ns)\<union>new (fst n_ns)) \<and> \<mu> V\<^sub>n \<eta> \<in> next (fst n_ns))
     \<and> (\<forall>nd\<in>snd n_ns.
         \<mu> V\<^sub>n \<eta> \<in> old nd \<and> name nd \<in> incoming (fst n_ns)
         \<longrightarrow> {\<mu>, \<eta>}\<subseteq>old nd \<or>
            (\<eta>\<in>old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old (fst n_ns)\<union>new (fst n_ns)))"

abbreviation
  "release_propag__rslt \<mu> \<eta> ns \<equiv>
     \<forall>nd\<in>ns.
       \<forall>nd'\<in>ns.
         \<mu> V\<^sub>n \<eta> \<in> old nd \<and> name nd \<in> incoming nd'
         \<longrightarrow> {\<mu>, \<eta>}\<subseteq>old nd \<or>
            (\<eta>\<in>old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old nd')"

lemma expand_release_propag:
  fixes n_ns :: "_ \<times> 'a node set"
  assumes "release_propag__assm \<mu> \<eta> n_ns
           \<and> release_propag__rslt \<mu> \<eta> (snd n_ns)
           \<and> expand_assm_incoming n_ns
           \<and> expand_name_ident (snd n_ns)" (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (\<lambda>r. release_propag__rslt \<mu> \<eta> (snd r))"
      (is "_ \<le> SPEC ?P")
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case (goal1 f x n ns)
    then show ?case
    proof (simp, rule_tac upd_incoming__ident)
      case goal1
        { fix nd :: "'a node" and nd' :: "'a node"
          let ?V_prop = "\<mu> V\<^sub>n \<eta> \<in> old nd \<and> name nd \<in> incoming nd'
            \<longrightarrow> {\<mu>, \<eta>} \<subseteq> old nd \<or> \<eta> \<in> old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old nd'"
          assume "nd\<in>ns" and nd'_elem: "nd'\<in>upd_incoming n ns"
          { assume "nd'\<in>ns"
            then have ?V_prop using `nd\<in>ns` goal1 by auto }
          moreover
          { assume "nd'\<notin>ns" 
            and V_in_nd: "\<mu> V\<^sub>n \<eta> \<in> old nd" and "name nd \<in>incoming nd'"
            with upd_incoming__elem[of nd' n ns] nd'_elem
            obtain nd'' where "nd''\<in>ns"
              and nd'_eq: "nd' = nd''\<lparr>incoming := incoming n \<union> incoming nd''\<rparr>"
              and old_eq: "old nd'' = old n" 
              by auto
            { assume "name nd \<in> incoming n"
              with V_in_nd `nd\<in>ns`
              have "{\<mu>, \<eta>} \<subseteq> old nd \<or> \<eta> \<in> old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old n" 
                using goal1 by auto
              then have "{\<mu>, \<eta>} \<subseteq> old nd \<or> \<eta> \<in> old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old nd'" 
                using nd'_eq old_eq by simp }
            moreover
            { assume "name nd \<notin> incoming n"
              then have "name nd \<in> incoming nd''" 
                using `name nd \<in>incoming nd'` nd'_eq by simp
              then have "{\<mu>, \<eta>} \<subseteq> old nd \<or> \<eta> \<in> old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old nd'" 
                unfolding nd'_eq
              using `nd\<in>ns` `nd''\<in>ns` V_in_nd goal1 by auto }
            ultimately have "{\<mu>, \<eta>} \<subseteq> old nd \<or> \<eta> \<in> old nd \<and> \<mu> V\<^sub>n \<eta> \<in> old nd'" 
              by fast }
          ultimately have ?V_prop by auto }
        then show ?case by auto
    next
      case goal2 then show ?case by simp
    qed
next
  case (goal2 f x n ns)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and f_sup: "\<And>x. f x \<le> expand x" by auto
    have Q: "?Q (n, ns)" using goal2 by auto
    from Q have name_le: "name n < expand_new_name (name n)" by auto
    let ?x' = "(\<lparr>name = expand_new_name (name n),
                 incoming = {name n}, new = next n,
                 old = {}, next = {}\<rparr>, {n} \<union> ns)"
    have Q'1: "expand_assm_incoming ?x'\<and> expand_name_ident (snd ?x')"
    using `new n = {}` Q[THEN conjunct2, THEN conjunct2] name_le by force
    have Q'2: "release_propag__assm \<mu> \<eta> ?x' \<and> release_propag__rslt \<mu> \<eta> (snd ?x')"
      using Q `new n = {}` by auto

    show ?case using `new n = {}` unfolding `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak[where 
        Q = "\<lambda>_ r. expand_name_ident (snd r)" and P = "\<lambda>_. ?P"])
      case goal1 then show ?case using Q'1
        by (rule_tac order_trans, 
          rule_tac f_sup, 
          rule_tac expand_name_propag__name_ident) auto
    next
      case goal2 then show ?case using Q'1 Q'2 by (rule_tac step) simp
    next
      case (goal3 nm nds) then show ?case by simp
    qed
next
  case goal3 then show ?case by auto
next
  case (goal4 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>q. \<psi> = prop\<^sub>n(q) \<or> \<psi> = nprop\<^sub>n(q))" by simp
    have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and Q: "?Q (n, ns)" using goal4 by simp+
    show ?case using Q goal_assms by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal5 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> \<psi> = true\<^sub>n" by simp
    have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and Q: "?Q (n, ns)" using goal5 by simp+
    show ?case using Q goal_assms by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)" by simp
    have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and Q: "?Q (n, ns)" using goal7 by simp+
    show ?case using Q goal_assms by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)"
      by (cases \<psi>) auto
    have Q: "?Q (n, ns)"
     and step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
     and f_sup: "\<And>x. f x \<le> expand x" using goal8 by auto
    let ?x = "(n\<lparr>new := new n - {\<psi>}, new := new1 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
          old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>), 
                              next := next1 \<psi> \<union> next (n\<lparr>new := new n - {\<psi>}\<rparr>)
        \<rparr>, ns)"
    let ?props = "\<lambda>x r. expand_rslt_exist_eq x r 
      \<and> expand_rslt_incoming r \<and> expand_rslt_name x r \<and> expand_name_ident (snd r)"

    show ?case using goal_assms Q unfolding case_prod_unfold `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak_nested2[where Q = "?props ?x"])
      case goal1 then show ?case
        by (rule_tac SPEC_rule_conjI,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_rslt_exist_eq,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_name_propag) simp+
    next
      case goal2 then show ?case 
        by (rule_tac SPEC_rule_param2[where P = "\<lambda>_. ?P"], rule_tac step) auto
    next
      case (goal3 nm nds)
        let ?x' = "(n\<lparr>new := new n - {\<psi>},
           name := fst (nm, nds),
           new := new2 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
           old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>)\<rparr>, nds)"
        show ?case using goal3
        proof (rule_tac step)
          case goal1
            then have "expand_assm_incoming ?x'" by auto
            moreover
            have nds_ident: "expand_name_ident (snd ?x')" using goal1 by simp
            moreover
            have "(\<mu> V\<^sub>n \<eta> \<in> old (fst ?x')
                   \<longrightarrow> ({\<mu>, \<eta>}\<subseteq>old (fst ?x') \<union> new (fst ?x') 
                        \<or> (\<eta>\<in>old (fst ?x')\<union>new (fst ?x') 
                           \<and> \<mu> V\<^sub>n \<eta> \<in> next (fst ?x'))))"
            using Q[THEN conjunct1] goal_assms by auto
            moreover
            have "release_propag__rslt \<mu> \<eta> (snd ?x')" using goal1 by simp
            moreover
            have name_nds_eq: 
              "name ` nds = name ` ns \<union> name ` {nd\<in>nds. name nd \<ge> name n}" 
              using goal1 by auto
            have "\<forall>nd\<in>nds. (\<mu> V\<^sub>n \<eta> \<in> old nd \<and> name nd \<in> incoming (fst ?x'))
                       \<longrightarrow> ({\<mu>, \<eta>}\<subseteq>old nd 
                            \<or> (\<eta>\<in>old nd \<and> \<mu> V\<^sub>n \<eta> \<in>old (fst ?x')\<union>new (fst ?x')))"
             (is "\<forall>nd\<in>nds. ?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd")
            proof
              fix nd
              assume "nd\<in>nds"
              { assume loc_assm: "name nd\<in>name ` ns"
                then obtain n' where "n'\<in>ns" and "name n' = name nd" by auto
                moreover then obtain nd' where "nd'\<in>nds" 
                  and n'_nd'_eq: "expand_rslt_exist_eq__node n' nd'" 
                  using goal1 by auto
                ultimately have "nd = nd'" using nds_ident `nd\<in>nds` loc_assm 
                  by auto
                moreover from goal1 have "?assm n n' \<longrightarrow> ?concl n n'" 
                  using `n'\<in>ns` by auto
                ultimately have "?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd" 
                  using n'_nd'_eq by auto }
              moreover
              { assume "name nd\<notin>name ` ns"
                with name_nds_eq `nd\<in>nds` have "name nd \<ge> name n" by auto
                then have "\<not> (?assm (fst ?x') nd)" using goal1 by auto }
              ultimately show "?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd" by auto
            qed
            ultimately show ?case by simp
        qed
    qed    
qed

lemma release_propag_on_create_graph:
  shows "create_graph \<phi>
         \<le> SPEC (\<lambda>nds. \<forall>n\<in>nds. \<forall>n'\<in>nds. \<mu> V\<^sub>n \<eta>\<in>old n \<and> name n\<in>incoming n'
                                          \<longrightarrow> ({\<mu>, \<eta>}\<subseteq>old n \<or> \<eta>\<in>old n \<and> \<mu> V\<^sub>n \<eta>\<in>old n'))"
  unfolding create_graph_def
  by (intro refine_vcg, 
    rule_tac order_trans, 
    rule_tac expand_release_propag) (auto simp add:expand_new_name_expand_init)


abbreviation
  "until_propag__assm f g n_ns \<equiv>
     (f U\<^sub>n g \<in> old (fst n_ns) 
      \<longrightarrow> (g\<in>old (fst n_ns)\<union>new (fst n_ns) 
            \<or> (f\<in>old (fst n_ns)\<union>new (fst n_ns) \<and> f U\<^sub>n g \<in> next (fst n_ns))))
     \<and> (\<forall>nd\<in>snd n_ns. f U\<^sub>n g \<in> old nd \<and> name nd \<in> incoming (fst n_ns)
        \<longrightarrow> (g\<in>old nd \<or> (f\<in>old nd \<and> f U\<^sub>n g \<in>old (fst n_ns)\<union>new (fst n_ns))))"

abbreviation
  "until_propag__rslt f g ns \<equiv>
     \<forall>n\<in>ns. \<forall>nd\<in>ns. f U\<^sub>n g \<in> old n \<and> name n \<in> incoming nd
                                  \<longrightarrow> (g \<in> old n \<or> (f\<in>old n \<and> f U\<^sub>n g \<in> old nd))"

lemma expand_until_propag:
  fixes n_ns :: "_ \<times> 'a node set"
  assumes "until_propag__assm \<mu> \<eta> n_ns
           \<and> until_propag__rslt \<mu> \<eta> (snd n_ns)
           \<and> expand_assm_incoming n_ns
           \<and> expand_name_ident (snd n_ns)" (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (\<lambda>r. until_propag__rslt \<mu> \<eta> (snd r))"
      (is "_ \<le> SPEC ?P")
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case (goal1 f x n ns)
    then show ?case
    proof (simp, rule_tac upd_incoming__ident)
      case goal1
        { fix nd :: "'a node" and nd' :: "'a node"
          let ?U_prop = "\<mu> U\<^sub>n \<eta> \<in> old nd \<and> name nd \<in> incoming nd'
                               \<longrightarrow> \<eta> \<in> old nd \<or> \<mu> \<in> old nd \<and> \<mu> U\<^sub>n \<eta> \<in> old nd'"
          assume "nd\<in>ns" and nd'_elem: "nd'\<in>upd_incoming n ns"
          { assume "nd'\<in>ns"
            then have ?U_prop using `nd\<in>ns` goal1 by auto }
          moreover
          { assume "nd'\<notin>ns" and 
            U_in_nd: "\<mu> U\<^sub>n \<eta> \<in> old nd" and "name nd \<in>incoming nd'"
            with upd_incoming__elem[of nd' n ns] nd'_elem
            obtain nd'' where "nd''\<in>ns"
              and nd'_eq: "nd' = nd''\<lparr>incoming := incoming n \<union> incoming nd''\<rparr>"
              and old_eq: "old nd'' = old n" by auto
            { assume "name nd \<in> incoming n"
              with U_in_nd `nd\<in>ns`
              have "\<eta> \<in> old nd \<or> \<mu> \<in> old nd \<and> \<mu> U\<^sub>n \<eta> \<in> old n" using goal1 by auto
              then have "\<eta> \<in> old nd \<or> \<mu> \<in> old nd \<and> \<mu> U\<^sub>n \<eta> \<in> old nd'" 
                using nd'_eq old_eq by simp }
            moreover
            { assume "name nd \<notin> incoming n"
              then have "name nd \<in> incoming nd''" 
                using `name nd \<in>incoming nd'` nd'_eq by simp
              then have "\<eta> \<in> old nd \<or> \<mu> \<in> old nd \<and> \<mu> U\<^sub>n \<eta> \<in> old nd'" unfolding nd'_eq
              using `nd\<in>ns` `nd''\<in>ns` U_in_nd goal1 by auto }
            ultimately have "\<eta> \<in> old nd \<or> \<mu> \<in> old nd \<and> \<mu> U\<^sub>n \<eta> \<in> old nd'" by fast }
          ultimately have ?U_prop by auto }
        then show ?case by auto
    next
      case goal2 then show ?case by simp
    qed
next
  case (goal2 f x n ns)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and f_sup: "\<And>x. f x \<le> expand x" by auto
    have Q: "?Q (n, ns)" using goal2 by auto
    from Q have name_le: "name n < expand_new_name (name n)" by auto
    let ?x' = "(\<lparr>name = expand_new_name (name n),
                 incoming = {name n}, new = next n,
                 old = {}, next = {}\<rparr>, {n} \<union> ns)"
    have Q'1: "expand_assm_incoming ?x'\<and> expand_name_ident (snd ?x')"
    using `new n = {}` Q[THEN conjunct2, THEN conjunct2] name_le by force
    have Q'2: "until_propag__assm \<mu> \<eta> ?x' \<and> until_propag__rslt \<mu> \<eta> (snd ?x')"
      using Q `new n = {}` by auto

    show ?case using `new n = {}` unfolding `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak[where 
        Q = "\<lambda>_ r. expand_name_ident (snd r)" and P = "\<lambda>_. ?P"])
      case goal1 then show ?case using Q'1
        by (rule_tac order_trans, 
          rule_tac f_sup, 
          rule_tac expand_name_propag__name_ident) auto
    next
      case goal2 then show ?case using Q'1 Q'2 by (rule_tac step) simp
    next
      case (goal3 nm nds) then show ?case by simp
    qed
next
  case goal3 then show ?case by auto
next
  case (goal4 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal4 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal5 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal5 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal7 by (rule_tac SPEC_rule_param2, rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)"
      by (cases \<psi>) auto
    have Q: "?Q (n, ns)"
     and step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
     and f_sup: "\<And>x. f x \<le> expand x" using goal8 by auto
    let ?x = "(n\<lparr>new := new n - {\<psi>}, new := new1 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
          old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>), 
                              next := next1 \<psi> \<union> next (n\<lparr>new := new n - {\<psi>}\<rparr>)
         \<rparr>, ns)"
    let ?props = "\<lambda>x r. expand_rslt_exist_eq x r 
      \<and> expand_rslt_incoming r \<and> expand_rslt_name x r \<and> expand_name_ident (snd r)"

    show ?case using goal_assms Q unfolding case_prod_unfold `x = (n, ns)`

    proof (rule_tac SPEC_rule_weak_nested2[where Q = "?props ?x"])
      case goal1 then show ?case
        by (rule_tac SPEC_rule_conjI,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_rslt_exist_eq,
               rule_tac order_trans,
               rule_tac f_sup,
               rule_tac expand_name_propag) simp+
    next
      case goal2 then show ?case 
        by (rule_tac SPEC_rule_param2[where P = "\<lambda>_. ?P"], rule_tac step) auto
    next
      case (goal3 nm nds)
        let ?x' = "(n\<lparr>new := new n - {\<psi>},
           name := fst (nm, nds),
           new := new2 \<psi> \<union> new (n\<lparr>new := new n - {\<psi>}\<rparr>),
           old := {\<psi>} \<union> old (n\<lparr>new := new n - {\<psi>}\<rparr>)\<rparr>, nds)"
        show ?case using goal3
        proof (rule_tac step)
          case goal1
            then have "expand_assm_incoming ?x'" by auto
            moreover
            have nds_ident: "expand_name_ident (snd ?x')" using goal1 by simp
            moreover
            have "(\<mu> U\<^sub>n \<eta> \<in> old (fst ?x')
                   \<longrightarrow> (\<eta>\<in>old (fst ?x')\<union>new (fst ?x') 
                        \<or> (\<mu>\<in>old (fst ?x')\<union>new (fst ?x') 
                           \<and> \<mu> U\<^sub>n \<eta> \<in> next (fst ?x'))))"
            using Q[THEN conjunct1] goal_assms by auto
            moreover
            have "until_propag__rslt \<mu> \<eta> (snd ?x')" using goal1 by simp
            moreover
            have name_nds_eq: 
              "name ` nds = name ` ns \<union> name ` {nd\<in>nds. name nd \<ge> name n}" 
              using goal1 by auto
            have "\<forall>nd\<in>nds. (\<mu> U\<^sub>n \<eta> \<in> old nd \<and> name nd \<in> incoming (fst ?x'))
              \<longrightarrow> (\<eta>\<in>old nd \<or> (\<mu>\<in>old nd \<and> \<mu> U\<^sub>n \<eta> \<in>old (fst ?x')\<union>new (fst ?x')))"
             (is "\<forall>nd\<in>nds. ?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd")
            proof
              fix nd
              assume "nd\<in>nds"
              { assume loc_assm: "name nd\<in>name ` ns"
                then obtain n' where "n'\<in>ns" and "name n' = name nd" by auto
                moreover then obtain nd' where "nd'\<in>nds" 
                  and n'_nd'_eq: "expand_rslt_exist_eq__node n' nd'" 
                  using goal1 by auto
                ultimately have "nd = nd'" 
                  using nds_ident `nd\<in>nds` loc_assm by auto
                moreover from goal1 have "?assm n n' \<longrightarrow> ?concl n n'" 
                  using `n'\<in>ns` by auto
                ultimately have "?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd" 
                  using n'_nd'_eq by auto }
              moreover
              { assume "name nd\<notin>name ` ns"
                with name_nds_eq `nd\<in>nds` have "name nd \<ge> name n" by auto
                then have "\<not> (?assm (fst ?x') nd)" using goal1 by auto }
              ultimately show "?assm (fst ?x') nd \<longrightarrow> ?concl (fst ?x') nd" by auto
            qed
            ultimately show ?case by simp
        qed
    qed    
qed

lemma until_propag_on_create_graph:
  shows "create_graph \<phi>
         \<le> SPEC (\<lambda>nds. \<forall>n\<in>nds. \<forall>n'\<in>nds. \<mu> U\<^sub>n \<eta>\<in>old n \<and> name n\<in>incoming n'
  \<longrightarrow> (\<eta>\<in>old n \<or> \<mu>\<in>old n \<and> \<mu> U\<^sub>n \<eta>\<in>old n'))"
  unfolding create_graph_def
  by (intro refine_vcg, 
    rule_tac order_trans, 
    rule_tac expand_until_propag) (auto simp add:expand_new_name_expand_init)


definition all_subfrmls :: "'a node \<Rightarrow> 'a frml set"
where
  "all_subfrmls n \<equiv> \<Union>(subfrmlsn ` (new n \<union> old n \<union> next n))"

lemma all_subfrmls__UnionD:
  assumes "(\<Union>x\<in>A. subfrmlsn x) \<subseteq> B"
      and "x\<in>A" and "y\<in>subfrmlsn x"
    shows "y\<in>B"
proof -
  note subfrmlsn_id[of x]
  also have "subfrmlsn x \<subseteq> (\<Union>x\<in>A. subfrmlsn x)" using assms by auto
  finally show ?thesis using assms by auto
qed


lemma expand_all_subfrmls_propag:
  assumes "all_subfrmls (fst n_ns) \<subseteq> B
           \<and> (\<forall>nd\<in>snd n_ns. all_subfrmls nd \<subseteq> B)" (is "?Q n_ns")
    shows "expand n_ns \<le> SPEC (\<lambda>r. \<forall>nd\<in>snd r. all_subfrmls nd \<subseteq> B)"
      (is "_ \<le> SPEC ?P")
using assms
proof (rule_tac expand_rec_rule[where \<Phi>="?Q"], simp, intro refine_vcg)
  case goal1 then show ?case
    proof (simp, rule_tac upd_incoming__ident)
      case goal1 then show ?case by auto
    next
      case goal2 then show ?case by (simp add:all_subfrmls_def)
    qed
next
  case goal2 then show ?case by (auto simp add:all_subfrmls_def)
next
  case goal3 then show ?case by (auto simp add:all_subfrmls_def)
next
  case (goal4 f)
    then have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" by simp+
    show ?case using goal4 by (rule_tac step) (auto simp add:all_subfrmls_def)
next
  case (goal5 f _ n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> \<psi> = true\<^sub>n" by simp
    have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and Q: "?Q (n, ns)" using goal5 by simp+
    show ?case using Q goal_assms 
      by (rule_tac step) (auto dest:all_subfrmls__UnionD simp add:all_subfrmls_def)
next
  case goal6 then show ?case by auto
next
  case (goal7 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)" by simp
    have step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P"
      and Q: "?Q (n, ns)" using goal7 by simp+
    show ?case using Q goal_assms 
      by (rule_tac step) (auto dest:all_subfrmls__UnionD simp add:all_subfrmls_def)
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n 
      \<and> \<not> (\<exists>q. \<psi> = prop\<^sub>n(q) \<or> \<psi> = nprop\<^sub>n(q)) 
      \<and> \<psi> \<noteq> true\<^sub>n \<and> \<psi> \<noteq> false\<^sub>n 
      \<and>  \<not> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)
      \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)" 
      by (cases \<psi>) auto
    have Q: "?Q (n, ns)" and step: "\<And>x. ?Q x \<Longrightarrow> f x \<le> SPEC ?P" 
      using goal8 by simp+
    show ?case using goal_assms Q unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_nested2)
      case goal1 then show ?case 
        by (rule_tac step) (auto 
          dest:all_subfrmls__UnionD 
          simp add:all_subfrmls_def)
    next
      case goal2 then show ?case 
        by (rule_tac step) (auto 
          dest:all_subfrmls__UnionD 
          simp add:all_subfrmls_def)
    qed
qed

lemma old_propag_on_create_graph:
  shows "create_graph \<phi> \<le> SPEC (\<lambda>nds. \<forall>n\<in>nds. old n \<subseteq> subfrmlsn \<phi>)"
  unfolding create_graph_def
  by (intro refine_vcg, 
    rule_tac order_trans, 
    rule_tac expand_all_subfrmls_propag[where B = "subfrmlsn \<phi>"])
   (force simp add:all_subfrmls_def expand_new_name_expand_init)+

lemma L4_2__aux:
  assumes run: "ipath gba.E \<sigma>"
      and "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> 0)"
      and "\<forall>j. (\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i)) \<longrightarrow> \<eta> \<notin> old (\<sigma> j)"
    shows "\<forall>i. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i) \<and> \<eta> \<notin> old (\<sigma> i)"
proof -
  { fix j
    have "\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i)" (is "?sbthm j")
    proof (induct j)
      show "?sbthm 0" by auto
    next
      fix k
      assume step: "?sbthm k"
      then have \<sigma>_k_prop: "\<eta> \<notin> old (\<sigma> k) 
        \<and> \<sigma> k\<in>qs \<and> \<sigma> (Suc k)\<in>qs 
        \<and> name (\<sigma> k) \<in> incoming (\<sigma> (Suc k))"
      using assms run_propag_on_create_graph[OF run] by auto
      with inres_SPEC[OF res until_propag_on_create_graph[where \<mu> = \<mu> and \<eta> = \<eta>]]
      have "{\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> k)" (is "?subsetthm")
      proof (cases k)
        assume "k = 0"
        with assms \<sigma>_k_prop 
          inres_SPEC[OF res until_propag_on_create_graph[where \<mu> = \<mu> and \<eta> = \<eta>]]
        show ?subsetthm by auto
      next
        fix l
        assume "k = Suc l"
        then have "{\<mu>, \<mu> U\<^sub>n \<eta>}\<subseteq>old (\<sigma> l) \<and> \<eta>\<notin>old (\<sigma> l) 
          \<and> \<sigma> l\<in>qs \<and> \<sigma> k\<in>qs
          \<and> name (\<sigma> l)\<in>incoming (\<sigma> k)"
        using step assms run_propag_on_create_graph[OF run] by auto
        with inres_SPEC[OF res until_propag_on_create_graph[where \<mu> = \<mu> and \<eta> = \<eta>]]
        have "\<mu> U\<^sub>n \<eta>\<in>old (\<sigma> k)" by auto
        with \<sigma>_k_prop 
          inres_SPEC[OF res until_propag_on_create_graph[where \<mu> = \<mu> and \<eta> = \<eta>]]
        show ?subsetthm by auto
      qed
      with step show "?sbthm (Suc k)" by (metis less_SucE)
    qed }
  with assms show ?thesis by auto
qed

lemma L4_2a:
  assumes "ipath gba.E \<sigma>"
      and "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> 0)"
    shows "(\<forall>i. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i) \<and> \<eta> \<notin> old (\<sigma> i))
           \<or> (\<exists>j. (\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i)) \<and> \<eta> \<in> old (\<sigma> j))"
      (is "?A \<or> ?B")
proof -
  { assume "\<not> ?B"
    then have "?A" using assms by (rule_tac L4_2__aux) blast+
    then have "?A \<or> ?B" by fast }
  moreover
  { assume "?B"
    then have "?A \<or> ?B" by blast }
  ultimately show ?thesis by fast
qed

lemma L4_2b:
  assumes run: "ipath gba.E \<sigma>"
      and "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> 0)"
      and ACC: "gba.is_acc \<sigma>"
    shows "\<exists>j. (\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i)) \<and> \<eta> \<in> old (\<sigma> j)"
proof(rule ccontr)
  assume "\<not> ?thesis"
  then have contr: "\<forall>i. {\<mu>, \<mu> U\<^sub>n \<eta>}\<subseteq>old(\<sigma> i) \<and> \<eta>\<notin>old(\<sigma> i)" 
    using assms L4_2a[of \<sigma> \<mu> \<eta>] by blast


  def S\<equiv>"{q \<in> qs. \<mu> U\<^sub>n \<eta> \<in> old q \<longrightarrow> \<eta> \<in> old q}"

  from assms inres_SPEC[OF res old_propag_on_create_graph] 
    create_gba_from_nodes__ipath
  have "\<mu> U\<^sub>n \<eta> \<in> subfrmlsn \<phi>" by (metis assms(2) set_mp)
  then have "S\<in>gbg_F(create_gba_from_nodes \<phi> qs)"
    unfolding S_def create_gba_from_nodes_def by auto
  with ACC have 1: "\<exists>\<^sub>\<infinity>i. \<sigma> i \<in> S" unfolding gba.is_acc_def by blast

  from INFM_EX[OF 1]
  obtain k where "\<sigma> k \<in> qs" and "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> k) \<longrightarrow> \<eta> \<in> old (\<sigma> k)" 
    unfolding S_def by auto

  moreover have "{\<mu>, \<mu> U\<^sub>n \<eta>}\<subseteq>old(\<sigma> k) \<and> \<eta>\<notin>old(\<sigma> k)" using contr by auto
  ultimately show "False" by auto
qed

lemma L4_2c:
  assumes run: "ipath gba.E \<sigma>"
      and "\<mu> V\<^sub>n \<eta> \<in> old (\<sigma> 0)"
    shows "\<forall>i. \<eta> \<in> old (\<sigma> i) \<or> (\<exists>j<i. \<mu> \<in> old (\<sigma> j))"
proof -
  { fix i
    have "{\<eta>, \<mu> V\<^sub>n \<eta>} \<subseteq> old (\<sigma> i) \<or> (\<exists>j<i. \<mu> \<in> old (\<sigma> j))" (is "?thm i")
    proof (induct i)
      case 0 
        have "\<sigma> 0\<in>qs \<and> \<sigma> 1\<in>qs \<and> name (\<sigma> 0) \<in> incoming (\<sigma> 1)"
        using create_gba_from_nodes__ipath assms by auto
        then show ?case 
          using assms inres_SPEC[OF res release_propag_on_create_graph, of \<mu> \<eta>]
          by auto
    next
      case (Suc k)
        note `?thm k`
        moreover
        { assume "{\<eta>, \<mu> V\<^sub>n \<eta>} \<subseteq> old (\<sigma> k)"
          moreover
          have "\<sigma> k\<in>qs \<and> \<sigma> (Suc k)\<in>qs \<and> name (\<sigma> k) \<in> incoming (\<sigma> (Suc k))"
          using create_gba_from_nodes__ipath assms by auto
          ultimately have "\<mu> \<in> old (\<sigma> k) \<or> \<mu> V\<^sub>n \<eta> \<in> old (\<sigma> (Suc k))"
            using assms inres_SPEC[OF res release_propag_on_create_graph, of \<mu> \<eta>]
            by auto
          moreover
          { assume "\<mu> \<in> old (\<sigma> k)"
            then have ?case by blast }
          moreover
          { assume "\<mu> V\<^sub>n \<eta> \<in> old (\<sigma> (Suc k))"
            moreover
            have "\<sigma> (Suc k)\<in>qs \<and> \<sigma> (Suc (Suc k))\<in>qs 
              \<and> name (\<sigma> (Suc k)) \<in> incoming (\<sigma> (Suc (Suc k)))"
            using create_gba_from_nodes__ipath assms by auto
            ultimately have ?case 
              using assms 
                inres_SPEC[OF res release_propag_on_create_graph, of \<mu> \<eta>] 
              by auto }
          ultimately have ?case by fast }
        moreover
        { assume "\<exists>j<k. \<mu> \<in> old (\<sigma> j)"
          then have ?case by auto }
        ultimately show ?case by auto
    qed }
  then show ?thesis by auto
qed

lemma L4_8':
  assumes "ipath gba.E \<sigma>" (is "?inf_run \<sigma>")
  and "gba.is_acc \<sigma>" (is "?gbarel_accept \<sigma>")
  and "\<forall>i. gba.L (\<sigma> i) (\<xi> i)" (is "?lgbarel_accept \<xi> \<sigma>")
  and "\<psi> \<in> old (\<sigma> 0)"
  shows "\<xi> \<Turnstile>\<^sub>n \<psi>"
using assms proof (induct \<psi> arbitrary: \<sigma> \<xi>)
  case LTLnTrue show ?case by auto
next
  case LTLnFalse then show ?case
    using inres_SPEC[OF res false_propag_on_create_graph] 
      create_gba_from_nodes__ipath
    by (metis)
next
  case (LTLnProp p) then show ?case 
    unfolding create_gba_from_nodes_def by auto
next
  case (LTLnNProp p) then show ?case unfolding create_gba_from_nodes_def by auto
next
  case (LTLnAnd \<mu> \<eta>) then show ?case
    using inres_SPEC[OF res and_propag_on_create_graph, of \<mu> \<eta>] 
      create_gba_from_nodes__ipath
      by (metis insert_subset ltln_semantics.simps(5))
next
  case (LTLnOr \<mu> \<eta>)
    then have "\<mu> \<in> old (\<sigma> 0) \<or> \<eta> \<in> old (\<sigma> 0)" 
      using inres_SPEC[OF res or_propag_on_create_graph, of \<mu> \<eta>]
      create_gba_from_nodes__ipath 
      by (metis (full_types) Int_empty_left Int_insert_left_if0)
    moreover
    { assume "\<mu> \<in> old (\<sigma> 0)"
      with LTLnOr have "\<xi> \<Turnstile>\<^sub>n \<mu>" by auto }
    moreover
    { assume "\<eta> \<in> old (\<sigma> 0)"
      with LTLnOr have "\<xi> \<Turnstile>\<^sub>n \<eta>" by auto }
    ultimately show ?case by auto
next
  case (LTLnNext \<mu>)
    with create_gba_from_nodes__ipath[of \<sigma>]
    have "\<sigma> 0 \<in> qs \<and> \<sigma> 1 \<in> qs \<and> name (\<sigma> 0) \<in> incoming (\<sigma> 1)" by auto
    with inres_SPEC[OF res next_propag_on_create_graph, of \<mu>] 
    have "\<mu>\<in>old (suffix 1 \<sigma> 0)" using LTLnNext by auto
    moreover
    have "?inf_run (suffix 1 \<sigma>)" and "?gbarel_accept (suffix 1 \<sigma>)"
     and "?lgbarel_accept (suffix 1 \<xi>) (suffix 1 \<sigma> )"
    using LTLnNext create_gba_from_nodes__ipath 
    apply -
    apply (metis ipath_suffix)
    apply (auto simp del: suffix_nth) [] (* FIXME: 
      "\<lambda>a. suffix i \<sigma> a" is unfolded, but "suffix i \<sigma>" is not! *)
    apply (auto) []
    done
    ultimately show ?case using LTLnNext by simp
next
  case (LTLnUntil \<mu> \<eta>)
    then have "\<exists>j. (\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i)) \<and> \<eta> \<in> old (\<sigma> j)"
    using L4_2b by auto
    then obtain j where 
      \<sigma>_pre: "\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> i)" and "\<eta> \<in> old (suffix j \<sigma> 0)" 
      by auto
    moreover have "?inf_run (suffix j \<sigma>)" and "?gbarel_accept (suffix j \<sigma>)"
              and "?lgbarel_accept (suffix j \<xi>) (suffix j \<sigma> )" 
      unfolding limit_suffix
      using LTLnUntil create_gba_from_nodes__ipath
      apply -
      apply (metis ipath_suffix)
      apply (auto simp del: suffix_nth) [] (* FIXME: 
        "\<lambda>a. suffix i \<sigma> a" is unfolded, but "suffix i \<sigma>" is not! *)
      apply (auto) []
      done
    ultimately have "suffix j \<xi> \<Turnstile>\<^sub>n \<eta>" using LTLnUntil by simp
    moreover
    { fix i
      assume "i<j"
      have "?inf_run (suffix i \<sigma>)" and "?gbarel_accept (suffix i \<sigma>)"
       and "?lgbarel_accept (suffix i \<xi>) (suffix i \<sigma> )" unfolding limit_suffix
      using LTLnUntil create_gba_from_nodes__ipath
      apply -
      apply (metis ipath_suffix)
      apply (auto simp del: suffix_nth) [] (* FIXME: 
        "\<lambda>a. suffix i \<sigma> a" is unfolded, but "suffix i \<sigma>" is not! *)
      apply (auto) []
      done
      moreover
      have "\<mu>\<in>old (suffix i \<sigma> 0)" using \<sigma>_pre `i<j` by auto
      ultimately have "suffix i \<xi> \<Turnstile>\<^sub>n \<mu>" using LTLnUntil by simp }
    ultimately show ?case by auto
next
  case (LTLnRelease \<mu> \<eta>)
    { fix i
      assume "\<eta> \<in> old (\<sigma> i) \<or> (\<exists>j<i. \<mu> \<in> old (\<sigma> j))"
      moreover
      { assume "\<eta> \<in> old (\<sigma> i)"
        moreover
        have "?inf_run (suffix i \<sigma>)" and "?gbarel_accept (suffix i \<sigma>)"
         and "?lgbarel_accept (suffix i \<xi>) (suffix i \<sigma> )" unfolding limit_suffix
         using LTLnRelease create_gba_from_nodes__ipath 
        apply -
        apply (metis ipath_suffix)
        apply (auto simp del: suffix_nth) [] (* FIXME: 
          "\<lambda>a. suffix i \<sigma> a" is unfolded, but "suffix i \<sigma>" is not! *)
        apply (auto) []
        done
        ultimately have "suffix i \<xi> \<Turnstile>\<^sub>n \<eta>" using LTLnRelease by auto }
      moreover
      { assume "\<exists>j<i. \<mu> \<in> old (\<sigma> j)"
        then obtain j where "j<i" and "\<mu> \<in> old (\<sigma> j)" by auto
        moreover
        have "?inf_run (suffix j \<sigma>)" and "?gbarel_accept (suffix j \<sigma>)"
         and "?lgbarel_accept (suffix j \<xi>) (suffix j \<sigma> )" unfolding limit_suffix
         using LTLnRelease create_gba_from_nodes__ipath 
        apply -
        apply (metis ipath_suffix)
        apply (auto simp del: suffix_nth) [] (* FIXME: 
          "\<lambda>a. suffix i \<sigma> a" is unfolded, but "suffix i \<sigma>" is not! *)
        apply (auto) []
        done
        ultimately have "suffix j \<xi> \<Turnstile>\<^sub>n \<mu>" using LTLnRelease by auto
        then have "\<exists>j<i. suffix j \<xi> \<Turnstile>\<^sub>n \<mu>" using `j<i` by auto }
      ultimately have "suffix i \<xi> \<Turnstile>\<^sub>n \<eta> \<or> (\<exists>j<i. suffix j \<xi> \<Turnstile>\<^sub>n \<mu>)" by auto }
    then show ?case using LTLnRelease L4_2c by auto
qed


lemma L4_8:
  assumes "gba.is_acc_run \<sigma>"
      and "\<forall>i. gba.L (\<sigma> i) (\<xi> i)"
      and "\<psi> \<in> old (\<sigma> 0)"
    shows "\<xi> \<Turnstile>\<^sub>n \<psi>"
  using assms
  unfolding gba.is_acc_run_def gba.is_run_def
  using L4_8' by blast

lemma expand_expand_init_propag:
  assumes "(\<forall>nm\<in>incoming n'. nm < name n')
           \<and> name n' \<le> name (fst n_ns)
           \<and> (incoming n' \<inter> incoming (fst n_ns) \<noteq> {} 
              \<longrightarrow> new n' \<subseteq> old (fst n_ns) \<union> new (fst n_ns))
           " (is "?Q n_ns")
  and "\<forall>nd\<in>snd n_ns. \<forall>nm\<in>incoming n'. nm\<in>incoming nd \<longrightarrow> new n' \<subseteq> old nd" 
    (is "?P (snd n_ns)")
  shows "expand n_ns \<le> SPEC (\<lambda>r. name n'\<le>fst r \<and> ?P (snd r))"
  using assms
proof (rule_tac expand_rec_rule[where \<Phi>="\<lambda>x. ?Q x \<and> ?P (snd x)"], 
    simp, 
    intro refine_vcg)
  case (goal1 f x n ns)
    then have goal_assms: "new n = {} \<and> ?Q (n, ns) \<and> ?P ns" by simp
    { fix nd nm
      assume "nd\<in>upd_incoming n ns" and "nm\<in>incoming n'" and "nm\<in>incoming nd"
      { assume "nd\<in>ns"
        with goal_assms `nm\<in>incoming n'` `nm\<in>incoming nd` have "new n' \<subseteq> old nd"
          by auto }
      moreover
      { assume "nd\<notin>ns"
        with upd_incoming__elem[OF `nd\<in>upd_incoming n ns`]
        obtain nd' where "nd'\<in>ns"
                     and nd_eq: "nd = nd'\<lparr>incoming := incoming n \<union> incoming nd'\<rparr>"
                     and old_next_eq: "old nd' = old n \<and> next nd' = next n" by auto
        { assume "nm\<in>incoming nd'"
          with goal_assms `nm\<in>incoming n'` `nd'\<in>ns` have "new n' \<subseteq> old nd"
            unfolding nd_eq by auto }
        moreover
        { assume "nm\<in>incoming n"
          with nd_eq old_next_eq goal_assms `nm\<in>incoming n'` 
          have "new n' \<subseteq> old nd" 
            by auto }
        ultimately have "new n' \<subseteq> old nd" using `nm\<in>incoming nd` nd_eq by auto }
      ultimately have "new n' \<subseteq> old nd" by fast }
    then show ?case using goal1 by auto
next
  case (goal2 f x n ns)
    then have goal_assms: "new n = {} \<and> ?Q (n, ns) \<and> ?P ns"
      and step: "\<And>x. ?Q x \<and> ?P (snd x) 
        \<Longrightarrow> f x \<le> SPEC (\<lambda>r. name n' \<le> fst r \<and> ?P (snd r))" 
      by simp+

    then show ?case
    proof (rule_tac step)
      case goal1
        have expand_new_name_less: "name n < expand_new_name (name n)" by auto
        moreover have "name n \<notin> incoming n'" using goal_assms by auto
        ultimately show ?case using goal1 by auto
    qed
next
  case goal3 then show ?case by auto
next
  case (goal4 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) 
      \<Longrightarrow> f x \<le> SPEC (\<lambda>r. name n' \<le> fst r \<and> ?P (snd r))" 
      by simp+
    show ?case using goal4 by (rule_tac step) auto
next
  case (goal5 f x n ns)
    then have step: "\<And>x. ?Q x \<and> ?P (snd x) 
      \<Longrightarrow> f x \<le> SPEC (\<lambda>r. name n' \<le> fst r \<and> ?P (snd r))" 
      by simp+
    show ?case using goal5 by (rule_tac step) auto
next
  case goal6 then show ?case by auto
next
  case (goal7 f x n ns)
    then have step: 
      "\<And>x. ?Q x \<and> ?P (snd x) \<Longrightarrow> f x \<le> SPEC (\<lambda>r. name n' \<le> fst r \<and> ?P (snd r))" 
      by simp+
    show ?case using goal7 by (rule_tac step) auto
next
  case (goal8 f x n ns \<psi>)
    then have goal_assms: "\<psi> \<in> new n 
      \<and> \<not> (\<exists>q. \<psi> = prop\<^sub>n(q) \<or> \<psi> = nprop\<^sub>n(q)) 
      \<and> \<psi> \<noteq> true\<^sub>n \<and> \<psi> \<noteq> false\<^sub>n 
      \<and> \<not> (\<exists>\<nu> \<mu>. \<psi> = \<nu> and\<^sub>n \<mu> \<or> \<psi> = X\<^sub>n \<nu>)
      \<and> (\<exists>\<nu> \<mu>. \<psi> = \<nu> or\<^sub>n \<mu> \<or> \<psi> = \<nu> U\<^sub>n \<mu> \<or> \<psi> = \<nu> V\<^sub>n \<mu>)" 
      by (cases \<psi>) auto
    have QP: "?Q (n, ns) \<and> ?P ns" and 
      step: "\<And>x. ?Q x \<and> ?P (snd x) 
      \<Longrightarrow> f x \<le> SPEC (\<lambda>r. name n' \<le> fst r \<and> ?P (snd r))" 
      using goal8 by simp+
    show ?case using goal_assms QP unfolding case_prod_unfold `x = (n, ns)`
    proof (rule_tac SPEC_rule_nested2)
      case goal1 then show ?case by (rule_tac step) auto
    next
      case (goal2 nm nds) then show ?case by (rule_tac step) auto
    qed
qed

lemma expand_init_propag_on_create_graph:
  shows "create_graph \<phi> 
  \<le> SPEC(\<lambda>nds. \<forall>nd\<in>nds. expand_init\<in>incoming nd \<longrightarrow> \<phi> \<in> old nd)" 
unfolding create_graph_def
by (intro refine_vcg, rule_tac order_trans,
    rule_tac expand_expand_init_propag[where 
  n' = "\<lparr> name = expand_new_name expand_init, 
          incoming = {expand_init}, 
          new = {\<phi>}, 
          old = {}, 
          next = {} \<rparr>"]) (auto simp add:expand_new_name_expand_init)

lemma L4_6:
  assumes "q\<in>gba.V0"
    shows "\<phi>\<in>old q"
using assms inres_SPEC[OF res expand_init_propag_on_create_graph]
unfolding create_gba_from_nodes_def by auto

lemma L4_9:
  assumes acc: "gba.accept \<xi>"      
  shows "\<xi> \<Turnstile>\<^sub>n \<phi>"
proof -
  from acc obtain \<sigma> where accept: "gba.is_acc_run \<sigma> 
    \<and> (\<forall>i. gba.L (\<sigma> i) (\<xi> i))"
  unfolding gba.accept_def by auto
  then have "\<sigma> 0\<in>gba.V0" 
    unfolding gba.is_acc_run_def gba.is_run_def by simp
  with L4_6 have "\<phi>\<in>old (\<sigma> 0)" by auto
  with L4_8 accept show ?thesis by auto
qed

lemma L4_10:
  assumes "\<xi> \<Turnstile>\<^sub>n \<phi>"
    shows "gba.accept \<xi>"
proof -
  def \<sigma> \<equiv> "auto_run \<xi> qs"
  let ?G = "create_graph \<phi>"

  have \<sigma>_prop_0: "(\<sigma> 0)\<in>qs \<and> expand_init\<in>incoming(\<sigma> 0) \<and> auto_run_j 0 \<xi> (\<sigma> 0)"
    (is "?sbthm")
  using inres_SPEC[OF res L4_7[OF `\<xi> \<Turnstile>\<^sub>n \<phi>`]]
  unfolding \<sigma>_def auto_run.simps by (rule_tac someI_ex, simp) blast

  have \<sigma>_valid: "\<forall>j. \<sigma> j \<in> qs \<and> auto_run_j j \<xi> (\<sigma> j)" (is "\<forall>j. ?\<sigma>_valid j")
  proof
    fix j 
    show "?\<sigma>_valid j"
    proof(induct j)
      from \<sigma>_prop_0 show "?\<sigma>_valid 0" by fast
    next
      fix k 
      assume goal_assms: "\<sigma> k \<in> qs \<and> auto_run_j k \<xi> (\<sigma> k)"
      with inres_SPEC[OF res L4_5, of "suffix k \<xi>"]
      have sbthm: "\<exists>q'. q'\<in>qs \<and> name (\<sigma> k)\<in>incoming q' \<and> auto_run_j (Suc k) \<xi> q'" 
        (is "\<exists>q'. ?sbthm q'") 
        by auto
      have "?sbthm (\<sigma> (Suc k))" using someI_ex[OF sbthm] 
      unfolding \<sigma>_def auto_run.simps by blast
      then show "?\<sigma>_valid (Suc k)" by fast
    qed
  qed

  have \<sigma>_prop_Suc: "\<And>k. \<sigma> k\<in> qs \<and> \<sigma> (Suc k)\<in>qs 
    \<and> name (\<sigma> k)\<in>incoming (\<sigma> (Suc k)) 
    \<and> auto_run_j (Suc k) \<xi> (\<sigma> (Suc k))"
  proof -
    fix k
    from \<sigma>_valid have "\<sigma> k \<in> qs" and "auto_run_j k \<xi> (\<sigma> k)" by blast+
    with inres_SPEC[OF res L4_5, of "suffix k \<xi>"]
    have sbthm: "\<exists>q'. q'\<in>qs \<and> name (\<sigma> k)\<in>incoming q' 
      \<and> auto_run_j (Suc k) \<xi> q'" (is "\<exists>q'. ?sbthm q'") 
      by auto
    show "\<sigma> k\<in> qs \<and> ?sbthm (\<sigma> (Suc k))" using `\<sigma> k\<in>qs` someI_ex[OF sbthm] 
      unfolding \<sigma>_def auto_run.simps by blast
  qed

  have \<sigma>_vnaccpt:
       "\<forall>k \<mu> \<eta>. \<mu> U\<^sub>n \<eta> \<in> old (\<sigma> k)
           \<longrightarrow> \<not> (\<forall>i. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> (k+i)) \<and>
                     \<eta> \<notin> old (\<sigma> (k+i)))"
  proof(clarify)
    fix k \<mu> \<eta>
    assume U_in: "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> k)"
     and cntr_prm: "\<forall>i. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> (k+i)) \<and>
                        \<eta> \<notin> old (\<sigma> (k+i))"

    have "suffix k \<xi> \<Turnstile>\<^sub>n \<mu> U\<^sub>n \<eta>" using U_in \<sigma>_valid by force
    then obtain i
          where "suffix (k+i) \<xi> \<Turnstile>\<^sub>n \<eta>"
            and "\<forall>j<i. suffix (k+j) \<xi> \<Turnstile>\<^sub>n \<mu>" by auto
    moreover
    have "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> (k+i)) \<and>
          \<eta> \<notin> old (\<sigma> (k+i))" using cntr_prm by auto
    ultimately show "False" using \<sigma>_valid by force
  qed

  have \<sigma>_exec: "gba.is_run \<sigma>" using \<sigma>_prop_0 \<sigma>_prop_Suc \<sigma>_valid
    unfolding gba.is_run_def ipath_def 
    unfolding create_gba_from_nodes_def
    by auto
  moreover
  have \<sigma>_vaccpt:
       "\<forall>k \<mu> \<eta>. \<mu> U\<^sub>n \<eta> \<in> old (\<sigma> k) \<longrightarrow>
                (\<exists>j. (\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> (k+i))) \<and>
                            \<eta> \<in> old (\<sigma> (k+j)))"
  proof(clarify)
    fix k \<mu> \<eta>
    assume U_in: "\<mu> U\<^sub>n \<eta> \<in> old (\<sigma> k)"
    then have "\<not> (\<forall>i. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (suffix k \<sigma> i) \<and> \<eta> \<notin> old (suffix k \<sigma> i))"
    using \<sigma>_vnaccpt[THEN allE, of k] by auto
    moreover have "suffix k \<sigma> 0 \<in> qs" using \<sigma>_valid by auto
    ultimately
    show "\<exists>j. (\<forall>i<j. {\<mu>, \<mu> U\<^sub>n \<eta>} \<subseteq> old (\<sigma> (k+i))) \<and> \<eta> \<in> old (\<sigma> (k+j))"
      apply -
      apply (rule make_pos_rule'[OF L4_2a])
      apply (fold suffix_def)
      apply (rule ipath_suffix)
      using \<sigma>_exec[unfolded gba.is_run_def] 
      apply simp
      
      using U_in apply simp

      apply simp
      done
  qed
  
  have "gba.is_acc \<sigma>"
    unfolding gba.is_acc_def
  proof
    fix S
    assume "S\<in>gba.F"
    then obtain \<mu> \<eta> where
          S_eq: "S = {q \<in> qs. \<mu> U\<^sub>n \<eta> \<in> old q \<longrightarrow> \<eta> \<in> old q}"
      and "\<mu> U\<^sub>n \<eta> \<in> subfrmlsn \<phi>" 
      by (auto simp add: create_gba_from_nodes_def)

    have range_subset: "range \<sigma> \<subseteq> qs"
    proof
      fix q
      assume "q\<in>range \<sigma>"
      with full_SetCompr_eq[of \<sigma>] obtain k where "q = \<sigma> k" by auto
      then show "q \<in> qs" using \<sigma>_valid by auto
    qed
    with limit_nonempty[of \<sigma>]
         limit_in_range[of \<sigma>]
         finite_subset[OF range_subset]
         inres_SPEC[OF res create_graph_finite]
    obtain q where q_in_limit: "q \<in> limit \<sigma>"
             and q_is_node: "q\<in>qs" by auto


    then show "\<exists>\<^sub>\<infinity>i. \<sigma> i \<in> S"
    proof(cases "\<mu> U\<^sub>n \<eta> \<in> old q")
      assume "\<mu> U\<^sub>n \<eta> \<notin> old q"
      with S_eq q_in_limit q_is_node
      show ?thesis
        by (auto simp: limit_iff_frequent intro: INFM_mono)
    next
      assume "\<mu> U\<^sub>n \<eta> \<in> old q"
      obtain k where q_eq: "q = \<sigma> k" using q_in_limit
      unfolding limit_iff_frequent by (metis (lifting, full_types) INFM_nat_le)

      have "\<exists>\<^sub>\<infinity> k. \<eta> \<in> old (\<sigma> k)" unfolding INFM_nat
      proof(rule ccontr)
        assume "\<not> (\<forall>m. \<exists>n>m. \<eta> \<in> old (\<sigma> n))"
        then obtain m
              where "\<forall>n>m. \<eta> \<notin> old (\<sigma> n)" by auto
        moreover
        from q_eq q_in_limit limit_iff_frequent[of q \<sigma>]
             INFM_nat[of "\<lambda>n. \<sigma> n = q"]
        obtain n where "m<n"
                   and \<sigma>n_eq: "\<sigma> n = \<sigma> k" by auto
        moreover
        obtain j
         where "\<eta> \<in> old (\<sigma> (n+j))"
         using  \<sigma>_vaccpt `\<mu> U\<^sub>n \<eta> \<in> old q` unfolding q_eq
            by (fold \<sigma>n_eq) force

        ultimately show "False" by auto
      qed

      then have "\<exists>\<^sub>\<infinity> k. \<sigma> k \<in> qs \<and> \<eta> \<in> old (\<sigma> k)" 
        using \<sigma>_valid by (auto intro:INF_mono)
      then show "\<exists>\<^sub>\<infinity> k. \<sigma> k \<in> S" unfolding S_eq by (rule INFM_mono) simp
    qed
  qed
  moreover
  have "\<forall>i. gba.L (\<sigma> i) (\<xi> i)" (is "\<forall>i. ?sbthm i")
  proof
    fix i
    from \<sigma>_valid have [simp]: "\<sigma> i \<in> qs" by auto
    have "\<forall>\<psi>\<in>old (\<sigma> i). suffix i \<xi> \<Turnstile>\<^sub>n \<psi>" using \<sigma>_valid by auto
    then show "?sbthm i" unfolding create_gba_from_nodes_def by auto
  qed

  ultimately show ?thesis 
    unfolding gba.accept_def gba.is_acc_run_def by blast
qed

end
end

lemma create_graph__name_ident:
    shows "create_graph \<phi> \<le> SPEC (\<lambda>nds. \<forall>q\<in>nds. \<exists>!q'\<in>nds. name q = name q')"
using assms unfolding create_graph_def
by (intro refine_vcg, 
  rule_tac order_trans, 
  rule_tac expand_name_propag__name_ident) 
  (auto simp add:expand_new_name_expand_init)

corollary create_graph__name_inj:
  shows "create_graph \<phi> \<le> SPEC (\<lambda>nds. inj_on name nds)"
  apply (rule order_trans[OF create_graph__name_ident])
  apply (auto intro: inj_onI)
  done


definition
  "create_gba \<phi>
   \<equiv> do { nds \<leftarrow> create_graph\<^sub>T \<phi>;
          RETURN (create_gba_from_nodes \<phi> nds) }"

lemma create_graph_precond: "create_graph \<phi> 
  \<le> SPEC (create_gba_from_nodes_precond \<phi>)"
  apply (clarsimp simp: pw_le_iff refine_pw_simps create_graph_nofail)
  apply unfold_locales
  by simp
  
lemma create_gba__invar:
  "create_gba \<phi> \<le> SPEC gba"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph_precond])
  by (rule create_gba_from_nodes_precond.create_gba_from_nodes__invar)

lemma create_gba_acc: 
  shows "create_gba \<phi> \<le> SPEC(\<lambda>\<A>. \<forall>\<xi>. gba.accept \<A> \<xi> \<longleftrightarrow> \<xi> \<Turnstile>\<^sub>n \<phi>)"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph_precond])
  using create_gba_from_nodes_precond.L4_9
  using create_gba_from_nodes_precond.L4_10
  by blast

lemma create_gba__name_inj: 
  shows "create_gba \<phi> \<le> SPEC(\<lambda>\<A>. (inj_on name (g_V \<A>)))"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph__name_inj])
  apply (auto simp: create_gba_from_nodes_def)
  done

lemma create_gba__fin: 
  shows "create_gba \<phi> \<le> SPEC(\<lambda>\<A>. (finite (g_V \<A>)))"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph_finite])
  apply (auto simp: create_gba_from_nodes_def)
  done

lemma create_graph_old_finite: 
  "create_graph \<phi> \<le> SPEC (\<lambda>nds. \<forall>nd\<in>nds. finite (old nd))"
proof -
  show ?thesis 
    unfolding create_graph_def create_graph_eq_create_graph\<^sub>T[symmetric]
    unfolding expand_def
    apply (intro refine_vcg)
    apply (rule_tac order_trans)
    apply (rule_tac REC_le_RECT)
    apply (fold expand\<^sub>T_def)
    apply (rule_tac order_trans[OF expand_term_prop]) 
    apply auto[1]
    apply (rule_tac SPEC_rule)
    apply auto
    by (metis infinite_super subfrmlsn_finite)
qed

lemma create_gba__old_fin: 
  shows "create_gba \<phi> \<le> SPEC(\<lambda>\<A>. \<forall>nd\<in>g_V \<A>. finite (old nd))"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph_old_finite])
  apply (simp add: create_gba_from_nodes_def)
  done

lemma create_gba__incoming_exists: 
  shows "create_gba \<phi> 
  \<le> SPEC(\<lambda>\<A>. \<forall>nd\<in>g_V \<A>. incoming nd \<subseteq> insert expand_init (name ` (g_V \<A>)))"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph__incoming_name_exist])
  apply (auto simp add: create_gba_from_nodes_def)
  done

lemma create_gba__no_init: 
  shows "create_gba \<phi> \<le> SPEC(\<lambda>\<A>. expand_init \<notin> name ` (g_V \<A>))"
  unfolding create_gba_def create_graph_eq_create_graph\<^sub>T[symmetric]
  apply (refine_rcg refine_vcg order_trans[OF create_graph__incoming_name_exist])
  apply (auto simp add: create_gba_from_nodes_def)
  done

definition "nds_invars nds \<equiv> 
  inj_on name nds 
  \<and> finite nds 
  \<and> expand_init \<notin> name`nds
  \<and> (\<forall>nd\<in>nds. 
    finite (old nd) 
    \<and> incoming nd \<subseteq> insert expand_init (name ` nds))"

lemma create_gba_nds_invars: "create_gba \<phi> \<le> SPEC (\<lambda>\<A>. nds_invars (g_V \<A>))"
  using create_gba__name_inj[of \<phi>] create_gba__fin[of \<phi>] 
    create_gba__old_fin[of \<phi>] create_gba__incoming_exists[of \<phi>] 
    create_gba__no_init[of \<phi>]
  unfolding nds_invars_def
  apply (simp add: refine_pw_simps pw_le_iff) 
  done

theorem T4_1:
  shows "create_gba \<phi> \<le> SPEC(
    \<lambda>\<A>. gba \<A>
    \<and> finite (g_V \<A>)
    \<and> (\<forall>\<xi>. gba.accept \<A> \<xi> \<longleftrightarrow> \<xi> \<Turnstile>\<^sub>n \<phi>) 
    \<and> (nds_invars (g_V \<A>)))"
  using create_gba__invar create_gba__fin create_gba_acc create_gba_nds_invars
  apply (simp add: refine_pw_simps pw_le_iff) 
  apply blast
  done

definition "create_name_gba \<phi> \<equiv> do {
  G \<leftarrow> create_gba \<phi>;
  ASSERT (nds_invars (g_V G));
  RETURN (gba_rename name G)
}"


theorem create_name_gba_correct:
  shows "create_name_gba \<phi> \<le> SPEC(
    \<lambda>\<A>. gba \<A> \<and> finite (g_V \<A>) \<and> (\<forall>\<xi>. gba.accept \<A> \<xi> \<longleftrightarrow> \<xi> \<Turnstile>\<^sub>n \<phi>))"
  unfolding create_name_gba_def
  apply (refine_rcg refine_vcg order_trans[OF T4_1])
  apply (simp_all add: nds_invars_def gba_rename_correct)
  done

definition create_name_igba :: "'a::linorder ltln \<Rightarrow> _" where 
"create_name_igba \<phi> \<equiv> do {
  A \<leftarrow> create_name_gba \<phi>;
  A' \<leftarrow> gba_to_idx A;
  stat_set_data_nres (card (g_V A)) (card (g_V0 A')) (igbg_num_acc A');
  RETURN A'
}"

lemma create_name_igba_correct: "create_name_igba \<phi> \<le> SPEC (\<lambda>G. 
  igba G \<and> finite (g_V G) \<and> (\<forall>\<xi>. igba.accept G \<xi> \<longleftrightarrow> \<xi> \<Turnstile>\<^sub>n \<phi>))"
  unfolding create_name_igba_def
  apply (refine_rcg
    order_trans[OF create_name_gba_correct]
    order_trans[OF gba.gba_to_idx_ext_correct]
    refine_vcg)
  apply clarsimp_all
proof -
  fix G :: "(nat, 'a set) gba_rec"
  fix A :: "nat set"
  assume 1: "gba G"
  assume 2: "finite (g_V G)" "A \<in> gbg_F G"
  interpret gba G using 1 by this
  show "finite A" using finite_V_Fe 2 by this
qed

(* For presentation in paper*)
context
  notes [refine_vcg] = order_trans[OF create_name_gba_correct] 
begin
lemma "create_name_igba \<phi> \<le> SPEC (\<lambda>G. 
  igba G \<and> (\<forall>\<xi>. igba.accept G \<xi> \<longleftrightarrow> \<xi> \<Turnstile>\<^sub>n \<phi>))"
  unfolding create_name_igba_def
proof (refine_rcg refine_vcg, clarsimp_all)
  fix G :: "(nat, 'a set) gba_rec"
  assume "gba G"
  then interpret gba G .
  note [refine_vcg] = order_trans[OF gba_to_idx_ext_correct]

  assume "\<forall>\<xi>. gba.accept G \<xi> = \<xi> \<Turnstile>\<^sub>n \<phi>" "finite (g_V G)"
  then show "gba_to_idx G \<le> SPEC (\<lambda>G'. igba G' \<and> (\<forall>\<xi>. igba.accept G' \<xi> = \<xi> \<Turnstile>\<^sub>n \<phi>))"
    by (refine_rcg refine_vcg) (auto intro: finite_V_Fe)
qed

end

end
