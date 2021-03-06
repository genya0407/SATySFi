
open MyUtil
open LengthInterface
open GraphicBase
open HorzBox


type t =
  | PDF of Pdf.t * Pdfpage.t Alist.t * file_path


type 'o op_funcs = {
  graphics   : (intermediate_horz_box list) GraphicD.t -> (point -> intermediate_horz_box list -> 'o list) -> 'o list;
  text       : horz_string_info -> point -> OutputText.t -> 'o list;
  math       : math_string_info -> point -> OutputText.t -> 'o list;
  image      : ImageInfo.key -> point -> length -> length -> 'o list;
  test_box   : color -> point -> length -> length -> 'o list;
  test_frame : color -> point -> length -> length -> length -> 'o list;
}


let pdfops_of_text hsinfo pt otxt =
  let tag = FontInfo.get_font_tag hsinfo.font_abbrev in
    GraphicD.pdfops_of_text pt tag hsinfo.text_font_size hsinfo.text_color otxt


let pdfops_of_math msinfo pt otxt =
  let tag = FontInfo.get_math_tag msinfo.math_font_abbrev in
    GraphicD.pdfops_of_text pt tag msinfo.math_font_size msinfo.math_color otxt


let pdfops_of_image imgkey pt wid hgt =
  let tag = ImageInfo.get_tag imgkey in
  let (xratio, yratio) = ImageInfo.get_ratio imgkey wid hgt in
    GraphicD.pdfops_of_image pt xratio yratio tag


let fs_pdf = {
  graphics   = GraphicD.to_pdfops;
  text       = pdfops_of_text;
  math       = pdfops_of_math;
  image      = pdfops_of_image;
  test_box   = GraphicD.pdfops_test_box;
  test_frame = GraphicD.pdfops_test_frame;
}


let color_show_space = DeviceRGB(0.0, 0.0, 1.0)
let color_show_bbox  = DeviceRGB(1.0, 0.5, 0.5)


let rec ops_of_evaled_horz_box (fs : 'o op_funcs) (pbinfo : page_break_info) yposbaseline (xpos, opacc) (evhb : evaled_horz_box) =
  let (wid, evhbmain) = evhb in
    match evhbmain with
    | EvHorzEmpty ->
        let opaccnew =
          if OptionState.debug_show_space () then
            let opsgr = fs.test_box color_show_space (xpos, yposbaseline) wid (Length.of_pdf_point 2.) in
              Alist.append opacc opsgr
          else
            opacc
        in
          (xpos +% wid, opaccnew)

    | EvHorzFrame(hgt_frame, dpt_frame, deco, imhblst) ->
        let gr_background =
          deco (xpos, yposbaseline) wid hgt_frame dpt_frame
            (* -- depth values are nonpositive -- *)
        in
        let opsgr = fs.graphics gr_background (pdfops_of_intermediate_horz_box_list fs pbinfo) in
        let opaccinit = Alist.append opacc opsgr in
        let (xposnew, opaccsub) =
          imhblst @|> (xpos, opaccinit) @|> List.fold_left (ops_of_evaled_horz_box fs pbinfo yposbaseline)
        in
        let ops_foreground = [] in  (* temporary *)
        let opaccnew = Alist.append opaccsub ops_foreground in
          (xposnew, opaccnew)

    | EvHorzString(hsinfo, hgt, dpt, otxt) ->
        let ops =
          let opsmain =
              fs.text hsinfo (xpos, yposbaseline +% hsinfo.rising) otxt
          in
          if OptionState.debug_show_bbox () then
            let opsgr = fs.test_frame color_show_bbox (xpos, yposbaseline) wid hgt dpt in
              List.append opsgr opsmain
          else
            opsmain
        in
        let opaccnew = Alist.append opacc ops in
          (xpos +% wid, opaccnew)

    | EvHorzMathGlyph(msinfo, hgt, dpt, otxt) ->
        let ops =
          let opsmain =
            fs.math msinfo (xpos, yposbaseline) otxt
          in
          if OptionState.debug_show_bbox () then
            let opsgr = fs.test_frame color_show_bbox (xpos, yposbaseline) wid hgt dpt in
              List.append opsgr opsmain
          else
            opsmain
        in
        let opaccnew = Alist.append opacc ops in
          (xpos +% wid, opaccnew)

    | EvHorzRising(hgt, dpt, lenrising, evhblst) ->
        let (_, opaccsub) =
          evhblst |> List.fold_left (ops_of_evaled_horz_box fs pbinfo (yposbaseline +% lenrising)) (xpos, opacc)
        in
        let opaccnew =
(*
          if OptionState.debug_show_bbox () then
            Alist.append opaccsub (GraphicD.pdfops_test_frame (xpos, yposbaseline) wid hgt dpt)
          else
*)
            opaccsub
        in
          (xpos +% wid, opaccnew)

    | EvHorzEmbeddedVert(hgt, dpt, evvblst) ->
        let ((_, _), opaccnew) = ops_of_evaled_vert_box_list fs pbinfo (xpos, yposbaseline +% hgt) opacc evvblst in
          (xpos +% wid, opaccnew)

    | EvHorzInlineGraphics(hgt, dpt, graphics) ->
        let gr =
          match graphics with
          | ImGraphicsFixed(grff)    -> grff (xpos, yposbaseline)
          | ImGraphicsVariable(grvf) -> grvf wid (xpos, yposbaseline)
        in
        let opsgr = pdfops_of_graphics fs pbinfo gr in
        let opaccsub = Alist.append opacc opsgr in
        let opaccnew =
          if OptionState.debug_show_bbox () then
            let opsgr = fs.test_frame color_show_bbox (xpos, yposbaseline) wid hgt dpt in
              Alist.append opaccsub opsgr
          else
            opaccsub
        in
          (xpos +% wid, opaccnew)

    | EvHorzInlineTabular(hgt, dpt, evtabular, widlst, lenlst, rulesf) ->
        let ops_tabular =
          ops_of_evaled_tabular fs pbinfo (xpos, yposbaseline +% hgt) evtabular
        in
        let (xacc, _) =
          widlst |> List.fold_left (fun (xacc, x) w ->
            let xnew = x +% w in
              (Alist.extend xacc xnew, xnew)
          ) (Alist.extend Alist.empty xpos, xpos)
        in
        let (yacc, _) =
          let yinit = yposbaseline +% hgt in
          lenlst |> List.fold_left (fun (yacc, y) l ->
            let ynew = y -% l in
              (Alist.extend yacc ynew, ynew)
          ) (Alist.extend Alist.empty yinit, yinit)
        in
        let gr = rulesf (Alist.to_list xacc) (Alist.to_list yacc) in
        let ops_rules = pdfops_of_graphics fs pbinfo gr in
        let opaccnew = Alist.append (Alist.append opacc ops_tabular) ops_rules in
          (xpos +% wid, opaccnew)

    | EvHorzInlineImage(hgt, imgkey) ->
        let ops_image =
          fs.image imgkey (xpos, yposbaseline) wid hgt
        in
        let opaccnew = Alist.append opacc ops_image in
          (xpos +% wid, opaccnew)

    | EvHorzHookPageBreak(pbinfo, hookf) ->
        hookf pbinfo (xpos, yposbaseline);  (* -- invokes the hook function -- *)
        (xpos +% wid, opacc)


and ops_of_evaled_tabular (fs : 'o op_funcs) (pbinfo : page_break_info) point evtabular =
  let (opaccnew, _) =
    evtabular |> List.fold_left (fun (opacc, (xpos, ypos)) (vlen, evcelllst) ->
      let (opaccnew, _) =
        evcelllst |> List.fold_left (fun (opacc, (xpos, ypos)) evcell ->
          match evcell with
          | EvEmptyCell(wid) ->
              (opacc, (xpos +% wid, ypos))

          | EvNormalCell((wid, hgt, dpt), evhblst) ->
              let yposbaseline = ypos -% hgt in
              let (_, opaccsub) =
                  evhblst |> List.fold_left (ops_of_evaled_horz_box fs pbinfo yposbaseline) (xpos, opacc)
              in
              let opaccnew =
(*
                (GraphicD.pdfops_test_frame (xpos, yposbaseline) wid hgt dpt) |> Alist.append
*)
                  opaccsub
              in
                (opaccnew, (xpos +% wid, ypos))

          | EvMultiCell((_, _, widsingle, widcell, hgt, dpt), evhblst) ->
              let yposbaseline = ypos -% hgt in
              let (_, opaccsub) =
                  evhblst |> List.fold_left (ops_of_evaled_horz_box fs pbinfo yposbaseline) (xpos, opacc)
              in
              let opaccnew =
(*
                (GraphicD.pdfops_test_frame (xpos, yposbaseline) widcell hgt dpt) |> Alist.append
*)
                  opaccsub
              in
                (opaccnew, (xpos +% widsingle, ypos))

        ) (opacc, (xpos, ypos))
      in
        (opaccnew, (xpos, ypos -% vlen))
    ) (Alist.empty, point)
  in
    Alist.to_list opaccnew


and ops_of_evaled_vert_box_list (fs : 'o op_funcs) pbinfo (xinit, yinit) opaccinit evvblst =
  evvblst @|> ((xinit, yinit), opaccinit) @|> List.fold_left (fun ((xpos, ypos), opacc) evvb ->
    match evvb with
    | EvVertFixedEmpty(vskip) ->
(*
        (* begin: for debug *)
        let opacc =
          List.rev_append
            (ops_test_box (0.5, 1.0, 0.5) (xpos +% (Length.of_pdf_point 50.), ypos) (Length.of_pdf_point 200.) vskip)
            opacc
        in
        (* end: for debug *)
*)
        ((xpos, ypos -% vskip), opacc)

    | EvVertLine(hgt, dpt, evhblst) ->
        let yposbaseline = ypos -% hgt in
        let (_, opaccend) =
          evhblst @|> (xpos, opacc) @|> List.fold_left (ops_of_evaled_horz_box fs pbinfo yposbaseline)
        in
(*
        (* begin: for debug *)
        let opaccend =
          List.rev_append (List.append
            (ops_test_box (1.0, 0.5, 0.5) (xpos, ypos) (Length.of_pdf_point 100.) hgt)
            (ops_test_box (1.0, 0.5, 0.5) (xpos, ypos -% hgt) (Length.of_pdf_point 100.) (Length.negate dpt)))
            opaccend in
        (* end: for debug *)
*)
          ((xpos, yposbaseline +% dpt), opaccend)

    | EvVertFrame(pads, _, deco, wid, evvblstsub) ->
        let xpossubinit = xpos +% pads.paddingL in
        let ypossubinit = ypos -% pads.paddingT in
        let ((_, ypossub), opaccsub) = ops_of_evaled_vert_box_list fs pbinfo (xpossubinit, ypossubinit) Alist.empty evvblstsub in
        let yposend = ypossub -% pads.paddingB in
        let gr = deco (xpos, yposend) wid (ypos -% yposend) Length.zero in
        let opsgr = pdfops_of_graphics fs pbinfo gr in
        let opaccframe = Alist.append opacc opsgr in
        let opaccnew = Alist.append opaccframe (Alist.to_list opaccsub) in
          ((xpos, yposend), opaccnew)
  )


and pdfops_of_intermediate_horz_box_list (fs : 'o op_funcs) (pbinfo : page_break_info) ((xpos, yposbaseline) : point) (imhblst : intermediate_horz_box list) : 'o list =
  let (evhblst, _) = PageInfo.embed_page_info pbinfo imhblst in
  let (_, opacc) =
      evhblst |> List.fold_left (ops_of_evaled_horz_box fs pbinfo yposbaseline) (xpos, Alist.empty)
  in
    Alist.to_list opacc


and pdfops_of_graphics (fs : 'o op_funcs) (pbinfo : page_break_info) gr =
  fs.graphics gr (pdfops_of_intermediate_horz_box_list fs pbinfo)


type contents = Pdfops.t Alist.t

type page =
  | Page of Pdfpaper.t * page_content_scheme * contents * page_break_info


let invert_coordinate paper_height (xraw, yraw) =
  (xraw, paper_height -% yraw)


let get_paper_height (paper : Pdfpaper.t) : length =
  let dpi = 300. in  (* temporary; should be variable *)
  let pdfpt = Pdfunits.convert dpi (Pdfpaper.unit paper) Pdfunits.PdfPoint (Pdfpaper.height paper) in
    Length.of_pdf_point pdfpt


let make_page (pagesize : page_size) (pbinfo : page_break_info) (pagecontsch : page_content_scheme) (evvblstbody : evaled_vert_box list) (evvblstfootnote : evaled_vert_box list) : page =
  let paper =
    match pagesize with
    | A0Paper                -> Pdfpaper.a0
    | A1Paper                -> Pdfpaper.a1
    | A2Paper                -> Pdfpaper.a2
    | A3Paper                -> Pdfpaper.a3
    | A4Paper                -> Pdfpaper.a4
    | A5Paper                -> Pdfpaper.a5
    | USLetter               -> Pdfpaper.usletter
    | USLegal                -> Pdfpaper.uslegal
    | UserDefinedPaper(w, h) -> Pdfpaper.make Pdfunits.PdfPoint (Length.to_pdf_point w) (Length.to_pdf_point h)
  in
  let paper_height = get_paper_height paper in

  let (_, opaccbody) =
    let pt_init = invert_coordinate paper_height pagecontsch.page_content_origin in
    ops_of_evaled_vert_box_list fs_pdf pbinfo pt_init Alist.empty evvblstbody
  in
  let (_, opaccfootnote) =
    let hgtfootnote = get_height_of_evaled_vert_box_list evvblstfootnote in
    let (xorg, yorg) = pagecontsch.page_content_origin in
    let hgtreq = pagecontsch.page_content_height in
    let pt_init = invert_coordinate paper_height (xorg, yorg +% hgtreq -% hgtfootnote) in
    ops_of_evaled_vert_box_list fs_pdf pbinfo pt_init Alist.empty evvblstfootnote
  in
  let opaccpage = Alist.cat opaccbody opaccfootnote in
    Page(paper, pagecontsch, opaccpage, pbinfo)


let write_page (Page(paper, pagecontsch, opaccpage, pbinfo) : page) (pagepartsf : page_parts_scheme_func) ((PDF(pdf, pageacc, flnm)) : t) : t =

  let paper_height = get_paper_height paper in

  let pagepartssch = pagepartsf pbinfo in  (* -- invokes the page-parts function -- *)
  let (evvblst_header, _) = pagepartssch.header_content |> PageInfo.embed_page_info_vert pbinfo in
  let pt_header = invert_coordinate paper_height pagepartssch.header_origin in
  let (_, opacc_header) = ops_of_evaled_vert_box_list fs_pdf pbinfo pt_header opaccpage evvblst_header in

  let (evvblst_footer, _) = pagepartssch.footer_content |> PageInfo.embed_page_info_vert pbinfo in
  let pt_footer = invert_coordinate paper_height pagepartssch.footer_origin in
  let (_, opacc_footer) = ops_of_evaled_vert_box_list fs_pdf pbinfo pt_footer opacc_header evvblst_footer in

  let oplst = Alist.to_list opacc_footer in

  let pdfobjstream = Pdfops.stream_of_ops oplst in

  Pdfcodec.encode_pdfstream pdf Pdfcodec.Flate pdfobjstream;
    (* -- conpresses the operatand/operator stream -- *)

  let pagenew =
    { (Pdfpage.blankpage paper) with
        Pdfpage.content = [pdfobjstream];
    }
  in
  let pagenew = Annotation.add_to_pdf pdf pagenew in
  let () = NamedDest.notify_pagebreak pbinfo.current_page_number in
    PDF(pdf, Alist.extend pageacc pagenew, flnm)


let create_empty_pdf (flnm : file_path) : t =
  let pdf = Pdf.empty () in
    PDF(pdf, Alist.empty, flnm)


let write_to_file ((PDF(pdf, pageacc, flnm)) : t) : unit =
  Logging.begin_to_embed_fonts ();
  let pdfdict_font = FontInfo.get_font_dictionary pdf in
  let pdfarr_procset =
    Pdf.Array(List.map (fun s -> Pdf.Name(s))
                ["/PDF"; "/Text"; "/ImageC"; "ImageB"; "ImageI";])
  in
  let pdfdict_xobject = ImageInfo.get_xobject_dictionary pdf in
  let ir_resources =
    Pdf.addobj pdf (Pdf.Dictionary[
      ("/Font"   , pdfdict_font);
      ("/XObject", pdfdict_xobject);
      ("/ProcSet", pdfarr_procset);
    ])
  in
  Logging.begin_to_write_page ();
  let pagelst =
    pageacc |> Alist.to_list |> List.map (fun page ->
      { page with Pdfpage.resources = Pdf.Indirect(ir_resources); }
    )
  in
  let (pdfsub, irpageroot) = Pdfpage.add_pagetree pagelst pdf in
  let pdfout = pdfsub |> (Pdfpage.add_root irpageroot [])
                      |> Outline.add_to_pdf
                      |> NamedDest.add_to_pdf
  in
    Pdfwrite.pdf_to_file pdfout flnm
